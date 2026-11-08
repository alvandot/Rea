import SwiftUI
import ReaCore

struct SettingsView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Sources") { ExtensionsView().environmentObject(app) }
                    NavigationLink("Tracking") { TrackingView().environmentObject(app) }
                    NavigationLink("Translation") { TranslationProviderView().environmentObject(app) }
                } header: {
                    Text("Integrations")
                }

                Section("Reading") {
                    NavigationLink("Reader Defaults") {
                        ReaderSettingsView(settings: $app.settings)
                    }
                    Toggle("Auto-translate pages", isOn: $app.settings.translationEnabled)
                }

                Section("Library") {
                    LabeledContent("Series", value: "\(app.series.count)")
                    LabeledContent("Reading", value: "\(app.series.filter { $0.status == .reading }.count)")
                    Button {
                        Task { await app.syncAllNow() }
                    } label: {
                        HStack {
                            Text("Sync Trackers Now")
                            Spacer()
                            if app.syncing { ProgressView() }
                        }
                    }
                    .disabled(app.syncing)
                }

                Section("Storage") {
                    NavigationLink("Local Import") {
                        LocalImportView().environmentObject(app)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Storage", value: "Core Data / CloudKit")
                    LabeledContent("Sources loaded", value: "\(app.sources.count)")
                }

                if let error = app.lastError {
                    Section("Last Error") {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: app.settings) { _, newValue in
                newValue.save()
                app.applyTranslationProvider()
            }
        }
    }
}
