import SwiftUI
import ReaCore

struct TrackingView: View {
    var series: Series?
    @EnvironmentObject var app: AppModel

    @State private var trackerIDs: [String] = []
    @State private var entries: [String: [TrackerEntry]] = [:]
    @State private var links: [String: TrackerLink] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var searchQuery = ""
    @State private var searchResults: [String: [TrackerSearchResult]] = [:]
    @State private var searching = false
    @StateObject private var oauth = OAuthCoordinator()

    var body: some View {
        List {
            Section {
                Button {
                    Task { await app.syncAllNow() }
                } label: {
                    HStack {
                        Text("Sync All Trackers")
                        Spacer()
                        if app.syncing { ProgressView() }
                    }
                }
                .disabled(app.syncing)
            }

            ForEach(trackerIDs, id: \.self) { trackerID in
                Section {
                    if let link = links[trackerID] {
                        linkedRow(trackerID: trackerID, link: link)
                    } else if series != nil {
                        searchBlock(trackerID: trackerID)
                    } else {
                        Text("No series linked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let list = entries[trackerID], !list.isEmpty {
                        ForEach(list) { entry in
                            HStack {
                                Text(entry.title.isEmpty ? entry.remoteID : entry.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(entry.progress)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(entry.status.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(trackerID == "myanimelist" ? "MyAnimeList" : "AniList")
                        Spacer()
                        Text(app.trackerStatuses[trackerID] ?? "—")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if (app.trackerStatuses[trackerID] ?? "").hasPrefix("Not linked") {
                        Button {
                            connect(trackerID)
                        } label: {
                            Text("Connect \(trackerID == "myanimelist" ? "MyAnimeList" : "AniList")")
                                .font(.caption)
                        }
                    }
                }
            }

            if let error {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(series == nil ? "Tracking" : "Tracking · \(series?.title ?? "")")
        .overlay {
            if loading && entries.isEmpty {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func linkedRow(trackerID: String, link: TrackerLink) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Linked")
                    .font(.subheadline)
                Text("Remote \(link.remoteID) · synced \(link.lastSyncedProgress) chapters")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Unlink", role: .destructive) {
                Task {
                    await app.tracking.unlink(seriesID: link.seriesID, trackerID: trackerID)
                    links[trackerID] = nil
                }
            }
            .font(.caption)
        }
    }

    private func searchBlock(trackerID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search on tracker", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search(trackerID: trackerID) } }
                Button("Find") { Task { await search(trackerID: trackerID) } }
                    .disabled(searchQuery.isEmpty || searching)
            }
            if let results = searchResults[trackerID], !results.isEmpty {
                ForEach(results) { result in
                    Button {
                        Task { await link(trackerID: trackerID, remoteID: result.id) }
                    } label: {
                        HStack {
                            Text(result.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "link")
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let trackers = await app.tracking.allTrackers()
        trackerIDs = trackers.map(\.id)
        if let series {
            for trackerID in trackerIDs {
                links[trackerID] = try? await app.tracking.linkFor(seriesID: series.id, trackerID: trackerID)
            }
        }
        for tracker in trackers {
            if let list = try? await tracker.list(status: nil) {
                entries[tracker.id] = list
            }
        }
    }

    private func search(trackerID: String) async {
        guard let tracker = await app.tracking.tracker(id: trackerID) else { return }
        searching = true
        error = nil
        defer { searching = false }
        do {
            searchResults[trackerID] = try await tracker.search(searchQuery)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func connect(_ trackerID: String) {
        guard let config = TrackerClientConfig.load(trackerID) else {
            error = "Add ReaTracker.\(trackerID) (ClientID/RedirectURI) to Info.plist first."
            return
        }
        oauth.start(trackerID, config: config)
    }

    private func link(trackerID: String, remoteID: String) async {
        guard let series else { return }
        do {
            try await app.tracking.link(seriesID: series.id, trackerID: trackerID, remoteID: remoteID)
            links[trackerID] = try await app.tracking.linkFor(seriesID: series.id, trackerID: trackerID)
            let chapters = (try? await app.store.chapters(for: series.id)) ?? []
            _ = await app.tracking.syncProgress(
                seriesID: series.id,
                chaptersRead: chapters.filter(\.isRead).count,
                status: .reading
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
