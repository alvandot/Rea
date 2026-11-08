import SwiftUI
import ReaCore

/// Page load pipeline for a chapter: resolves resources through the source,
/// then serves decoded image data to the pagers with a small prefetch window.
@MainActor
final class ReaderViewModel: ObservableObject {
    enum LoadState: Equatable {
        case loading, ready(Int), failed(String)
    }

    @Published private(set) var state: LoadState = .loading
    @Published private(set) var pages: [PageResource] = []
    @Published var currentPage: Int = 0
    @Published var showChrome = true
    @Published var showSettings = false
    @Published var bubbles: [Int: [TranslatedBubble]] = [:]
    @Published var translating = false
    @Published var translationError: String?

    let series: Series
    let chapter: Chapter
    private let source: any ContentSource
    private let app: AppModel
    private var cache: [Int: Data] = [:]

    init(series: Series, chapter: Chapter, source: any ContentSource, app: AppModel) {
        self.series = series
        self.chapter = chapter
        self.source = source
        self.app = app
    }

    func start() async {
        state = .loading
        cache.removeAll()
        bubbles.removeAll()
        do {
            let resources = try await source.pages(chapterRemoteID: chapter.remoteID)
            guard !resources.isEmpty else {
                state = .failed("This chapter has no pages.")
                return
            }
            pages = resources
            let saved = await app.savedPage(for: chapter)
            currentPage = min(max(0, saved), resources.count - 1)
            state = .ready(resources.count)
            await prefetch(around: currentPage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry() async { await start() }

    func data(for index: Int) async -> Data? {
        guard pages.indices.contains(index) else { return nil }
        if let cached = cache[index] { return cached }
        let resource = pages[index]
        do {
            let payload: Data
            switch resource.origin {
            case .remote(let url):
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                payload = data
            case .localFile(let url):
                payload = try Data(contentsOf: url, options: .mappedIfSafe)
            }
            cache[index] = payload
            return payload
        } catch {
            return nil
        }
    }

    func prefetch(around index: Int) async {
        guard !pages.isEmpty else { return }
        let lower = max(0, index - 1)
        let upper = min(pages.count - 1, index + 2)
        guard lower <= upper else { return }
        for i in lower...upper where cache[i] == nil {
            _ = await data(for: i)
        }
    }

    func pageChanged(_ index: Int) async {
        guard index != currentPage else { return }
        currentPage = index
        await prefetch(around: index)
        await app.saveProgress(chapter: chapter, page: index)
        if app.settings.translationEnabled {
            await translate(index)
        }
    }

    func translate(_ index: Int) async {
        guard bubbles[index] == nil, pages.indices.contains(index) else { return }
        translating = true
        translationError = nil
        defer { translating = false }
        do {
            let from = Language(code: app.settings.translationSourceCode,
                                name: app.settings.translationSourceCode.uppercased())
            let to = Language(code: app.settings.translationTargetCode,
                              name: app.settings.translationTargetCode.uppercased())
            bubbles[index] = try await app.translatePage(pages[index], from: from, to: to)
        } catch {
            translationError = error.localizedDescription
        }
    }
}

/// Resolves the chapter's source, then hands off to a view that owns the model.
struct ReaderView: View {
    let series: Series
    let chapter: Chapter

    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var source: (any ContentSource)?
    @State private var resolved = false

    var body: some View {
        Group {
            if let source {
                ReaderSessionView(series: series, chapter: chapter, source: source, app: app)
                    .environmentObject(app)
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 16) {
                        if resolved {
                            Image(systemName: "questionmark.folder").font(.largeTitle)
                            Text("Source unavailable")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
        .task {
            guard !resolved else { return }
            source = await app.registry.source(id: chapter.sourceID)
            resolved = true
        }
    }
}

private struct ReaderSessionView: View {
    let series: Series
    let chapter: Chapter
    let source: any ContentSource

    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ReaderViewModel

    init(series: Series, chapter: Chapter, source: any ContentSource, app: AppModel) {
        self.series = series
        self.chapter = chapter
        self.source = source
        _model = StateObject(wrappedValue: ReaderViewModel(
            series: series, chapter: chapter, source: source, app: app
        ))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: app.settings.backgroundHex).ignoresSafeArea()

            switch model.state {
            case .loading:
                ProgressView("Loading pages…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(message).multilineTextAlignment(.center).padding(.horizontal)
                    Button("Try Again") { Task { await model.retry() } }
                        .buttonStyle(.borderedProminent)
                    Button("Close") { dismiss() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                pager
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) { model.showChrome.toggle() }
                    }
            }

            if model.showChrome, case .ready = model.state {
                ReaderChrome(
                    title: "\(series.title) · \(chapter.name)",
                    page: model.currentPage,
                    pageCount: model.pages.count,
                    onClose: { dismiss() },
                    onSettings: { model.showSettings = true }
                )
            }
        }
        .statusBarHidden(!app.settings.verticalWebtoon)
        .sheet(isPresented: $model.showSettings) {
            ReaderSettingsView(settings: $app.settings)
                .environmentObject(app)
                .onDisappear { Task { await model.translate(model.currentPage) } }
        }
        .task {
            await model.start()
            await app.markChapterOpened(chapter: chapter, seriesID: series.id)
        }
    }

    @ViewBuilder
    private var pager: some View {
        if app.settings.verticalWebtoon {
            VerticalPager(model: model, fitWidth: app.settings.fitWidth, showOriginal: app.settings.showOriginalText)
        } else {
            HorizontalPager(model: model, rtl: app.settings.rtl, showOriginal: app.settings.showOriginalText)
        }
    }
}

// MARK: - Chrome

struct ReaderChrome: View {
    let title: String
    let page: Int
    let pageCount: Int
    let onClose: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "textformat.size")
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            if pageCount > 0 {
                Text("\(page + 1) / \(pageCount)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
