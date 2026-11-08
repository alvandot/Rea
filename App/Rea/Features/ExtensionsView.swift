import SwiftUI
import ReaCore

struct ExtensionsView: View {
    @EnvironmentObject var app: AppModel
    @State private var reloading = false

    private var builtins: [SourceInfo] {
        app.sources.filter { $0.kind == .builtin }
    }

    private var extensions: [SourceInfo] {
        app.sources.filter { $0.kind == .extensionSource }
    }

    var body: some View {
        List {
            Section {
                ForEach(builtins) { source in
                    sourceRow(source)
                }
            } header: {
                Text("Built-in Sources")
            } footer: {
                Text("Built into the app. Disable one to exclude it from search and Discover.")
            }

            Section {
                if extensions.isEmpty {
                    Text("No extensions installed. Drop a folder with manifest.json into the app's Documents/Extensions directory, then reload.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(extensions) { source in
                        sourceRow(source)
                    }
                }
            } header: {
                Text("Extensions")
            } footer: {
                Text("Script sources run in JavaScriptCore with a single network bridge (rea.fetch). No file or system access is exposed.")
            }
        }
        .navigationTitle("Sources")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        reloading = true
                        await app.reloadExtensions()
                        reloading = false
                    }
                } label: {
                    if reloading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(reloading)
            }
        }
    }

    private func sourceRow(_ source: SourceInfo) -> some View {
        Toggle(isOn: Binding(
            get: { !app.disabledSourceIDs.contains(source.id) },
            set: { app.setSourceEnabled(source.id, enabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                HStack(spacing: 6) {
                    Text(source.id)
                    Text("·")
                    Text(source.language.uppercased())
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}
