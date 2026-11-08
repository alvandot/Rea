import SwiftUI
import ReaCore

struct TranslationProviderView: View {
    @EnvironmentObject var app: AppModel
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $app.translationProvider) {
                    ForEach(TranslationProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: app.translationProvider) { _, _ in
                    app.applyTranslationProvider()
                }
            } footer: {
                Text("On-device uses Apple's Translation framework (iOS 17+). Remote calls a LibreTranslate-compatible endpoint.")
            }

            if app.translationProvider == .remote {
                Section("Remote Endpoint") {
                    TextField("Endpoint URL", text: $app.translationEndpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key (optional)", text: $app.translationAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        app.applyTranslationProvider()
                    } label: {
                        Label("Save Endpoint", systemImage: "checkmark.circle")
                    }
                }
            }

            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    HStack {
                        Text("Test Translation")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(testing)

                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Translation")
    }

    private func runTest() async {
        testing = true
        testResult = nil
        defer { testing = false }
        do {
            let translated = try await app.testTranslation(
                "Hello, this is a translation test.",
                from: .english,
                to: .indonesian
            )
            testResult = "Result: \(translated)"
        } catch {
            testResult = "Failed: \(error.localizedDescription)"
        }
    }
}
