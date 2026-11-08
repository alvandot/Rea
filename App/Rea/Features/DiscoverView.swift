import SwiftUI
import ReaCore

struct DiscoverView: View {
    @EnvironmentObject var app: AppModel
    @State private var section: DiscoverSection = .popular
    @State private var results: [Series] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(isSearching ? "Search" : "Discover")
                .searchable(text: $query, prompt: "Title, author, keyword")
                .onChange(of: query) { _, newValue in
                    runSearch(newValue)
                }
                .onAppear { loadIfNeeded() }
                .toolbar {
                    if !isSearching {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { Task { await load() } } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(isLoading)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && results.isEmpty {
            ProgressView("Fetching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, results.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if results.isEmpty {
            ContentUnavailableView {
                Label("Nothing here", systemImage: "magnifyingglass")
            } description: {
                Text(isSearching
                     ? "No matching series across your enabled sources."
                     : "No titles loaded from this section.")
            }
        } else {
            ScrollView {
                if !isSearching {
                    Picker("Section", selection: $section) {
                        ForEach(DiscoverSection.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onChange(of: section) { _, _ in Task { await load() } }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
                    ForEach(results) { item in
                        NavigationLink {
                            SeriesDetailView(series: libraryCopy(for: item))
                        } label: {
                            DiscoverCard(series: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task { await app.addToLibrary(item) }
                            } label: {
                                Label("Add to Library", systemImage: "plus.circle")
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func libraryCopy(for item: Series) -> Series {
        app.series.first { $0.id == item.id } ?? item
    }

    private func loadIfNeeded() {
        guard results.isEmpty, !isLoading else { return }
        Task { await load() }
    }

    private func runSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Task { await load() }
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            isLoading = true
            error = nil
            do {
                let found = try await app.search(trimmed)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            results = try await app.discover(section: section)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private struct DiscoverCard: View {
    let series: Series

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: series.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(2 / 3, contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                        .overlay(Image(systemName: "book.closed").foregroundStyle(.secondary))
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(series.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}
