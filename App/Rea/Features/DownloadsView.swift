import SwiftUI
import ReaCore

struct DownloadsView: View {
    @EnvironmentObject var app: AppModel

    private var active: [DownloadItem] {
        app.downloadItems
            .filter { $0.state == .queued || $0.state == .downloading }
            .sorted { $0.seriesTitle < $1.seriesTitle }
    }

    private var finished: [DownloadItem] {
        app.downloadItems
            .filter { $0.state == .completed }
            .sorted { $0.seriesTitle < $1.seriesTitle }
    }

    private var failed: [DownloadItem] {
        app.downloadItems
            .filter { $0.state == .failed || $0.state == .cancelled }
            .sorted { $0.seriesTitle < $1.seriesTitle }
    }

    var body: some View {
        NavigationStack {
            Group {
                if app.downloadItems.isEmpty {
                    ContentUnavailableView {
                        Label("No downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Download a chapter from any series to read it offline.")
                    }
                } else {
                    List {
                        if !active.isEmpty {
                            Section("In Progress") {
                                ForEach(active) { item in
                                    row(item, trailing: AnyView(
                                        Button {
                                            Task { await app.cancelDownload(chapterID: item.id) }
                                        } label: {
                                            Image(systemName: "xmark.circle")
                                        }
                                        .buttonStyle(.plain)
                                    ))
                                }
                            }
                        }

                        if !finished.isEmpty {
                            Section("Downloaded") {
                                ForEach(finished) { item in
                                    row(item, trailing: AnyView(
                                        Button(role: .destructive) {
                                            Task { await app.removeDownload(chapterID: item.id) }
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    ))
                                }
                                .onDelete { indexSet in
                                    let targets = indexSet.map { finished[$0] }
                                    Task {
                                        for target in targets {
                                            await app.removeDownload(chapterID: target.id)
                                        }
                                    }
                                }
                            }
                        }

                        if !failed.isEmpty {
                            Section("Failed") {
                                ForEach(failed) { item in
                                    row(item, trailing: AnyView(
                                        Button {
                                            Task { await app.removeDownload(chapterID: item.id) }
                                        } label: {
                                            Image(systemName: "xmark.circle")
                                        }
                                        .buttonStyle(.plain)
                                    ))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .refreshable { await app.refreshDownloadRecords() }
            .task { await app.refreshDownloadRecords() }
        }
    }

    private func row(_ item: DownloadItem, trailing: AnyView) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.seriesTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.chapterName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if item.state == .downloading || item.state == .queued {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                }
            }
            Spacer()
            Text(stateLabel(for: item))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            trailing
        }
        .padding(.vertical, 4)
    }

    private func stateLabel(for item: DownloadItem) -> String {
        switch item.state {
        case .queued: return "Queued"
        case .downloading: return "\(Int(item.progress * 100))%"
        case .completed: return "Saved"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}
