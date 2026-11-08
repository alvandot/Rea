import SwiftUI
import UniformTypeIdentifiers
import ReaCore

struct LocalImportView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var importing = false
    @State private var status: String?
    @State private var error: String?
    @State private var importingFolder = false

    private var acceptedTypes: [UTType] {
        var types: [UTType] = [.pdf, .zip]
        for ext in ["cbz", "cbr", "jpg", "jpeg", "png", "gif", "webp", "heic"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    var body: some View {
        List {
            Section {
                Button {
                    importing = true
                } label: {
                    Label("Import File", systemImage: "doc.badge.plus")
                }
                Button {
                    importingFolder = true
                } label: {
                    Label("Import Image Folder", systemImage: "folder.badge.plus")
                }
            } footer: {
                Text("CBZ, PDF, and single images are supported. CBR (RAR) archives are not. Imported files are copied into the app's private storage.")
            }

            if let status {
                Section {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Tips") {
                Label("Name CBZ files after the series title; it becomes the library entry.", systemImage: "info.circle")
                    .font(.caption)
                Label("Pages inside a CBZ must be ordered naturally (001, 002, …).", systemImage: "info.circle")
                    .font(.caption)
            }
        }
        .navigationTitle("Local Import")
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: acceptedTypes,
            allowsMultipleSelection: true
        ) { result in
            handle(result)
        }
        .fileImporter(
            isPresented: $importingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handle(result)
        }
    }

    private func handle(_ result: Result<[URL], Error>) {
        error = nil
        status = nil
        switch result {
        case .failure(let failure):
            error = failure.localizedDescription
        case .success(let urls):
            Task { await adopt(urls) }
        }
    }

    private func adopt(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        let store = LocalFileStore.default
        var imported = 0
        var failures: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let name = try store.adopt(url)
                if let series = try? await app.localSource.series(remoteID: name) {
                    var entry = series
                    entry.title = (name as NSString).deletingPathExtension
                    await app.addToLibrary(entry)
                    let chapters = try await app.localSource.chapters(seriesRemoteID: name)
                    try? await app.store.replaceChapters(for: entry.id, with: chapters)
                }
                imported += 1
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        status = "Imported \(imported) item\(imported == 1 ? "" : "s")."
        if !failures.isEmpty {
            error = "Could not import: \(failures.joined(separator: ", "))"
        }
        await app.reloadLibrary()
    }
}
