import SwiftUI
import ReaCore

struct SeriesDetailView: View {
    let series: Series

    @EnvironmentObject var app: AppModel
    @State private var chapters: [Chapter] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var readerTarget: ReaderTarget?
    @State private var showEdit = false
    @State private var showTracker = false

    struct ReaderTarget: Identifiable {
        let chapter: Chapter
        var id: UUID { chapter.id }
    }

    private var inLibrary: Bool {
        app.series.contains { $0.id == series.id }
    }

    private var liveSeries: Series {
        app.series.first { $0.id == series.id } ?? series
    }

    private var readCount: Int { chapters.filter(\.isRead).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                chaptersSection
            }
            .padding()
        }
        .navigationTitle(liveSeries.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: {
                        Label("Edit Details", systemImage: "pencil")
                    }
                    Button { showTracker = true } label: {
                        Label("Tracking", systemImage: "link")
                    }
                    Button {
                        Task { await refreshChapters() }
                    } label: {
                        Label("Refresh Chapters", systemImage: "arrow.clockwise")
                    }
                    if inLibrary {
                        Button(role: .destructive) {
                            Task { await app.remove(liveSeries) }
                        } label: {
                            Label("Remove from Library", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            SeriesEditView(series: liveSeries)
                .environmentObject(app)
        }
        .sheet(isPresented: $showTracker) {
            TrackingView(series: liveSeries)
                .environmentObject(app)
        }
        .fullScreenCover(item: $readerTarget) { target in
            ReaderView(series: liveSeries, chapter: target.chapter)
                .environmentObject(app)
                .onDisappear {
                    Task {
                        await loadLocalChapters()
                        if readCount > 0 {
                            _ = await app.tracking.syncProgress(
                                seriesID: liveSeries.id,
                                chaptersRead: readCount,
                                status: .reading
                            )
                        }
                    }
                }
        }
        .task { await loadChapters() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: liveSeries.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(2 / 3, contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                        .overlay(Image(systemName: "book.closed").foregroundStyle(.secondary))
                }
            }
            .frame(width: 120, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(liveSeries.title)
                    .font(.title3.weight(.semibold))
                if let author = liveSeries.author, !author.isEmpty {
                    Label(author, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let artist = liveSeries.artist, !artist.isEmpty, artist != liveSeries.author {
                    Label(artist, systemImage: "paintbrush")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(liveSeries.status.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    Text(liveSeries.rating.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !liveSeries.categories.isEmpty {
                    Text(liveSeries.categories.prefix(4).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("\(readCount) / \(chapters.count) read")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if let next = nextChapter {
                Button {
                    readerTarget = ReaderTarget(chapter: next)
                } label: {
                    Label(readCount > 0 ? "Continue" : "Start Reading", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if inLibrary {
                Button {
                    var updated = liveSeries
                    updated.isFavorite.toggle()
                    Task { await app.updateSeries(updated) }
                } label: {
                    Image(systemName: liveSeries.isFavorite ? "heart.fill" : "heart")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await addCurrentSeries() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var nextChapter: Chapter? {
        if let firstUnread = chapters.first(where: { !$0.isRead }) {
            return firstUnread
        }
        return chapters.last
    }

    @ViewBuilder
    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chapters").font(.headline)
                Spacer()
                if isLoading { ProgressView() }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if chapters.isEmpty && !isLoading {
                Text("No chapters found for this source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(chapters.reversed()) { chapter in
                    chapterRow(chapter)
                    Divider()
                }
            }
        }
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        HStack(spacing: 10) {
            Button {
                readerTarget = ReaderTarget(chapter: chapter)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.name)
                        .font(.subheadline)
                        .foregroundStyle(chapter.isRead ? .secondary : .primary)
                    HStack(spacing: 6) {
                        Text(String(format: "Ch. %.1f", chapter.number))
                        if let date = chapter.uploadedAt {
                            Text("·")
                            Text(date, style: .date)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await toggleRead(chapter) }
            } label: {
                Image(systemName: chapter.isRead ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chapter.isRead ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Button {
                Task { await app.download(chapter: chapter, series: liveSeries) }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Data

    private func loadChapters() async {
        guard inLibrary else {
            await fetchRemoteIntoState()
            return
        }
        await loadLocalChapters()
        if chapters.isEmpty {
            await fetchRemoteIntoState(persist: true)
        }
    }

    private func loadLocalChapters() async {
        chapters = (try? await app.store.chapters(for: series.id)) ?? []
    }

    /// Fetches from the remote source and rebinds every chapter to this local
    /// series id (sources may derive a different `seriesID`).
    private func fetchRemoteIntoState(persist: Bool = false) async {
        guard let source = await app.registry.source(id: series.sourceID) else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let remote = try await source.chapters(seriesRemoteID: series.remoteID)
            let rebound = remote.map { chapter -> Chapter in
                var copy = chapter
                copy.seriesID = series.id
                return copy
            }
            if persist && inLibrary {
                try? await app.store.replaceChapters(for: series.id, with: rebound)
                await loadLocalChapters()
            } else {
                chapters = rebound
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshChapters() async {
        if inLibrary {
            await fetchRemoteIntoState(persist: true)
        } else {
            await fetchRemoteIntoState()
        }
    }

    private func addCurrentSeries() async {
        var item = liveSeries
        item.isFavorite = true
        await app.addToLibrary(item)
        await fetchRemoteIntoState(persist: true)
    }

    private func toggleRead(_ chapter: Chapter) async {
        let newValue = !chapter.isRead
        if inLibrary {
            try? await app.store.setChapterRead(chapter.id, read: newValue)
            await loadLocalChapters()
        } else if let index = chapters.firstIndex(where: { $0.id == chapter.id }) {
            chapters[index].isRead = newValue
        }
        if inLibrary && newValue {
            _ = await app.tracking.syncProgress(
                seriesID: liveSeries.id,
                chaptersRead: chapters.filter(\.isRead).count,
                status: .reading
            )
        }
    }
}
