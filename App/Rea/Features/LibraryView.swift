import SwiftUI
import ReaCore

struct LibraryView: View {
    @EnvironmentObject var app: AppModel
    @State private var showImport = false
    @State private var resumeTarget: ResumeTarget?
    @State private var filter = LibraryFilter()

    struct ResumeTarget: Identifiable {
        let series: Series
        let chapter: Chapter
        var id: UUID { chapter.id }
    }

    private var readingNow: [Series] {
        app.series.filter { $0.status == .reading }
    }

    private var visible: [Series] {
        filter.apply(to: app.series)
    }

    var body: some View {
        NavigationStack {
            Group {
                if app.series.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Library")
            .searchable(text: $filter.query, prompt: "Search library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImport = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showImport) {
                LocalImportView()
                    .environmentObject(app)
            }
            .fullScreenCover(item: $resumeTarget) { target in
                ReaderView(series: target.series, chapter: target.chapter)
                    .environmentObject(app)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            scopeBar

            if visible.isEmpty {
                ContentUnavailableView {
                    Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No series in this filter. Try another status or clear the search.")
                } actions: {
                    Button("Clear Filters") { filter = LibraryFilter() }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 40)
            }

            if !readingNow.isEmpty && !filter.isActive {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Continue Reading")
                        .font(.headline)
                        .padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(readingNow) { item in
                                Button {
                                    Task { await resume(item) }
                                } label: {
                                    CoverCard(series: item, width: 120)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
                ForEach(visible) { item in
                    NavigationLink {
                        SeriesDetailView(series: item)
                    } label: {
                        CoverCard(series: item, width: nil)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await app.remove(item) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var scopeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.Scope.allCases, id: \.self) { scope in
                    Button {
                        filter.scope = scope
                    } label: {
                        Text(scope.title)
                            .font(.caption.weight(filter.scope == scope ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    filter.scope == scope
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.secondary.opacity(0.12)
                                )
                            )
                            .foregroundStyle(filter.scope == scope ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func resume(_ item: Series) async {
        if let point = await app.resumePoint(for: item.id) {
            resumeTarget = ResumeTarget(series: item, chapter: point.chapter)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your library is empty", systemImage: "books.vertical")
        } description: {
            Text("Add series from Discover or import a local CBZ, PDF, or image folder.")
        } actions: {
            Button("Import File") { showImport = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

struct CoverCard: View {
    let series: Series
    let width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: series.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(2 / 3, contentMode: .fill)
                case .failure:
                    placeholder
                default:
                    placeholder.overlay(ProgressView())
                }
            }
            .frame(width: width, height: width.map { $0 * 1.5 })
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(radius: 2, y: 1)

            Text(series.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.2))
            .overlay(Image(systemName: "book.closed").foregroundStyle(.secondary))
    }
}
