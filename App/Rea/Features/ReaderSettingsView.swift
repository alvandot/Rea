import SwiftUI
import ReaCore

struct ReaderSettingsView: View {
    @Binding var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    private let backgrounds: [(name: String, hex: String)] = [
        ("Black", "#000000"),
        ("White", "#FFFFFF"),
        ("Sepia", "#F4ECD8"),
        ("Slate", "#1B1D22")
    ]

    private let languages: [(code: String, name: String)] = [
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("en", "English"),
        ("id", "Indonesian"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Layout") {
                    Toggle("Vertical (webtoon) scroll", isOn: $settings.verticalWebtoon)
                    if !settings.verticalWebtoon {
                        Toggle("Right-to-left pages", isOn: $settings.rtl)
                    }
                    Toggle("Fit page width", isOn: $settings.fitWidth)
                }

                Section("Background") {
                    Picker("Background", selection: $settings.backgroundHex) {
                        ForEach(backgrounds, id: \.hex) { item in
                            HStack {
                                Circle()
                                    .fill(Color(hex: item.hex))
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.secondary.opacity(0.4)))
                                Text(item.name)
                            }
                            .tag(item.hex)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Translation") {
                    Toggle("Auto-translate pages", isOn: $settings.translationEnabled)
                    Toggle("Show original text", isOn: $settings.showOriginalText)
                        .disabled(!settings.translationEnabled)

                    Picker("From", selection: $settings.translationSourceCode) {
                        ForEach(languages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    Picker("To", selection: $settings.translationTargetCode) {
                        ForEach(languages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
