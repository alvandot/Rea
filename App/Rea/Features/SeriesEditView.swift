import SwiftUI
import ReaCore

struct SeriesEditView: View {
    let series: Series

    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var author: String
    @State private var summary: String
    @State private var status: ReadingStatus
    @State private var rating: ContentRating
    @State private var categories: String
    @State private var coverText: String
    @State private var saving = false
    @State private var error: String?

    init(series: Series) {
        self.series = series
        _title = State(initialValue: series.title)
        _author = State(initialValue: series.author ?? "")
        _summary = State(initialValue: series.summary ?? "")
        _status = State(initialValue: series.status)
        _rating = State(initialValue: series.rating)
        _categories = State(initialValue: series.categories.joined(separator: ", "))
        _coverText = State(initialValue: series.coverURL?.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Cover URL", text: $coverText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Classification") {
                    Picker("Status", selection: $status) {
                        ForEach(ReadingStatus.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    Picker("Content Rating", selection: $rating) {
                        ForEach(ContentRating.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    TextField("Categories (comma separated)", text: $categories)
                        .autocorrectionDisabled()
                }

                Section("Summary") {
                    TextEditor(text: $summary)
                        .frame(minHeight: 120)
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var updated = series
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorTrimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.author = authorTrimmed.isEmpty ? nil : authorTrimmed
        let summaryTrimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.summary = summaryTrimmed.isEmpty ? nil : summaryTrimmed
        updated.status = status
        updated.rating = rating
        updated.categories = categories
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        updated.coverURL = URL(string: coverText.trimmingCharacters(in: .whitespacesAndNewlines))

        await app.updateSeries(updated)

        if let trackerStatus = TrackerStatus.portal(status) {
            await app.tracking.syncProgress(
                seriesID: updated.id,
                chaptersRead: 0,
                status: trackerStatus
            )
        }
        dismiss()
    }
}

private extension TrackerStatus {
    static func portal(_ status: ReadingStatus) -> TrackerStatus? {
        switch status {
        case .reading: return .reading
        case .completed: return .completed
        case .onHold: return .onHold
        case .dropped: return .dropped
        case .planToRead: return .planToRead
        }
    }
}
