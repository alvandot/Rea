import Foundation
import SwiftUI
import ReaCore

struct SourceInfo: Identifiable, Hashable {
    enum Kind: String { case builtin = "Built-in", extensionSource = "Extension" }
    let id: String
    let name: String
    let language: String
    let kind: Kind
}

struct DownloadItem: Identifiable, Equatable {
    let id: UUID
    let seriesTitle: String
    let chapterName: String
    var progress: Double
    var state: DownloadState
}

@MainActor
final class AppModel: ObservableObject {
    @Published var series: [Series] = []
    @Published var settings = ReaderSettings.default
    @Published var lastError: String?
    @Published var sources: [SourceInfo] = []
    @Published var disabledSourceIDs: Set<String> = []
    @Published var downloadItems: [DownloadItem] = []

    let store: any LibraryStore
    let registry: SourceRegistry
    let downloads: DownloadManager

    let recognizer: any ImageTextRecognizer
    private(set) var translator: any TextTranslator

    @Published var translationProvider: TranslationProvider
    @Published var translationEndpoint: String
    @Published var translationAPIKey: String
    @Published var lastTranslationError: String?

    let tracking: TrackingManager
    @Published var trackerStatuses: [String: String] = [:]
    @Published var syncing = false
    @Published var syncResults: [TrackingManager.SyncOutcome] = []

    let mangadex = MangaDexSource(language: "en")
    let localSource = LocalSource()
    private let disabledKey = "rea.disabledSources"
    private var bubbleCache: [String: [TranslatedBubble]] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? caches

        #if canImport(CoreData)
        if let coreData = try? CoreDataLibraryStore(configuration: .cloudKit) {
            store = coreData
        } else {
            store = JSONLibraryStore(directory: docs)
        }
        #else
        store = JSONLibraryStore(directory: docs)
        #endif

        registry = SourceRegistry()
        downloads = DownloadManager(root: caches.appendingPathComponent("ReaDownloads", isDirectory: true))
        tracking = TrackingManager(links: JSONTrackerLinkStore(directory: docs))

        #if canImport(Vision)
        recognizer = VisionTextRecognizer()
        #else
        recognizer = NoOpTextRecognizer()
        #endif

        let defaults = UserDefaults.standard
        let provider = TranslationProvider(rawValue: defaults.string(forKey: TranslationProvider.key) ?? "") ?? .apple
        translationProvider = provider
        translationEndpoint = defaults.string(forKey: TranslationProvider.endpointKey)
            ?? "https://libretranslate.com/translate"
        translationAPIKey = defaults.string(forKey: TranslationProvider.apiKeyKey) ?? ""
        translator = IdentityTranslator()

        if let saved = defaults.stringArray(forKey: disabledKey) {
            disabledSourceIDs = Set(saved)
        }
        settings = ReaderSettings.load()
    }

    // MARK: - Boot

    func boot() async {
        await registry.register(mangadex)
        await registry.register(localSource)
        await loadExtensions()
        await registerTrackers()
        await refreshSources()
        await reloadLibrary()
        applyTranslationProvider()
        await observeDownloads()
    }

    private func registerTrackers() async {
        let malTokens = DefaultsTokenProvider(
            tokenKey: "rea.tracker.myanimelist.token",
            refreshKey: "rea.tracker.myanimelist.refresh"
        )
        let aniTokens = DefaultsTokenProvider(
            tokenKey: "rea.tracker.anilist.token",
            refreshKey: "rea.tracker.anilist.refresh"
        )
        await tracking.register(MyAnimeListTracker(tokens: malTokens))
        await tracking.register(AniListTracker(tokens: aniTokens))

        for tracker in await tracking.allTrackers() {
            let authed = await tracker.isAuthenticated
            trackerStatuses[tracker.id] = authed ? "Connected" : "Not linked"
        }
    }

    private func loadExtensions() async {
        var directories: [URL] = []
        if let bundled = Bundle.main.url(forResource: "Extensions", withExtension: nil) {
            directories.append(bundled)
        }
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            directories.append(docs.appendingPathComponent("Extensions", isDirectory: true))
        }
        for dir in directories where FileManager.default.fileExists(atPath: dir.path) {
            let runtime = JavaScriptCoreExtensionRuntime(directory: dir)
            guard let extensions = try? await runtime.availableManifests() else { continue }
            for ext in extensions {
                if let source = try? await runtime.makeSource(from: ext) {
                    await registry.register(source)
                }
            }
        }
    }

    func refreshSources() async {
        let all = await registry.all()
        sources = all.map { source in
            SourceInfo(
                id: source.id,
                name: source.name,
                language: source.language,
                kind: source.id.hasPrefix("ext.") ? .extensionSource : .builtin
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Re-registers bundled + Documents extensions and refreshes the list.
    func reloadExtensions() async {
        await loadExtensions()
        await refreshSources()
    }

    func enabledSources() async -> [any ContentSource] {
        await registry.all().filter { !disabledSourceIDs.contains($0.id) }
    }

    func setSourceEnabled(_ id: String, enabled: Bool) {
        if enabled { disabledSourceIDs.remove(id) } else { disabledSourceIDs.insert(id) }
        UserDefaults.standard.set(Array(disabledSourceIDs), forKey: disabledKey)
    }

    // MARK: - Library

    func reloadLibrary() async {
        do {
            series = try await store.loadSeries()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addToLibrary(_ item: Series) async {
        var item = item
        item.isFavorite = true
        do {
            try await store.upsert([item])
            await reloadLibrary()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateSeries(_ item: Series) async {
        do {
            try await store.upsert([item])
            await reloadLibrary()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func remove(_ item: Series) async {
        do {
            if item.sourceID == localSource.id {
                try? LocalFileStore.default.remove(name: item.remoteID)
            }
            try await store.delete(seriesID: item.id)
            for tracker in await tracking.allTrackers() {
                try? await tracking.unlink(seriesID: item.id, trackerID: tracker.id)
            }
            await reloadLibrary()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Reading progress

    struct ResumePoint: Sendable, Equatable {
        let chapter: Chapter
        let page: Int
    }

    func resumePoint(for seriesID: UUID) async -> ResumePoint? {
        let chapters = (try? await store.chapters(for: seriesID)) ?? []
        guard !chapters.isEmpty else { return nil }
        var best: ResumePoint?
        for chapter in chapters {
            guard let progress = try? await store.progress(for: chapter.id) else { continue }
            if let current = best, (chapter.number, progress.page) <= (current.chapter.number, current.page) {
                continue
            }
            best = ResumePoint(chapter: chapter, page: progress.page)
        }
        return best
    }

    func savedPage(for chapter: Chapter) async -> Int {
        (try? await store.progress(for: chapter.id))?.page ?? 0
    }

    func saveProgress(chapter: Chapter, page: Int) async {
        let progress = ReadingProgress(chapterID: chapter.id, page: page, updatedAt: .now)
        try? await store.saveProgress(progress)
    }

    // MARK: - Tracking

    /// Called when a reader opens; promotes the series to "reading".
    func markChapterOpened(chapter: Chapter, seriesID: UUID) async {
        if let index = series.firstIndex(where: { $0.id == seriesID }), series[index].status != .reading {
            var updated = series[index]
            updated.status = .reading
            await updateSeries(updated)
        }
    }

    func markChapterRead(chapter: Chapter, seriesID: UUID, chaptersRead: Int) async {
        try? await store.setChapterRead(chapter.id, read: true)
        let report = await tracking.syncProgress(seriesID: seriesID, chaptersRead: chaptersRead, status: .reading)
        if let trackerID = report.pushed.first {
            trackerStatuses[trackerID] = "Synced \(chaptersRead)"
        } else if let failure = report.failureSummary {
            trackerStatuses["error"] = failure
        }
    }

    func syncAllNow() async {
        guard !syncing else { return }
        syncing = true
        syncResults = []
        defer { syncing = false }

        var requests: [TrackingManager.SyncRequest] = []
        for item in series {
            let chapters = (try? await store.chapters(for: item.id)) ?? []
            let readCount = chapters.filter(\.isRead).count
            guard readCount > 0 else { continue }
            requests.append(TrackingManager.SyncRequest(
                seriesID: item.id,
                title: item.title,
                chaptersRead: readCount,
                status: .reading
            ))
        }

        for await outcome in await tracking.syncAll(requests) {
            syncResults.append(outcome)
        }
    }

    // MARK: - Discover / Search

    func discover(section: DiscoverSection) async throws -> [Series] {
        switch section {
        case .popular: return try await mangadex.popular(page: 1).items
        case .latest: return try await mangadex.latest(page: 1).items
        }
    }

    func search(_ query: String) async throws -> [Series] {
        let sources = await enabledSources()
        let results = await withTaskGroup(of: [Series].self) { group in
            for source in sources {
                group.addTask { (try? await source.search(query, page: 1).items) ?? [] }
            }
            var all: [Series] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }
        var seen = Set<UUID>()
        return results.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Downloads

    func download(chapter: Chapter, series: Series) async {
        guard let source = await registry.source(id: chapter.sourceID) else { return }
        guard !downloadItems.contains(where: { $0.id == chapter.id && $0.state != .failed }) else { return }
        do {
            let pages = try await source.pages(chapterRemoteID: chapter.remoteID)
            if let index = downloadItems.firstIndex(where: { $0.id == chapter.id }) {
                downloadItems[index].progress = 0
                downloadItems[index].state = .queued
            } else {
                downloadItems.append(DownloadItem(
                    id: chapter.id,
                    seriesTitle: series.title,
                    chapterName: chapter.name,
                    progress: 0,
                    state: .queued
                ))
            }
            _ = try await downloads.download(seriesID: series.id, chapterID: chapter.id, pages: pages)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func cancelDownload(chapterID: UUID) async {
        await downloads.cancel(chapterID: chapterID)
    }

    func removeDownload(chapterID: UUID) async {
        try? await downloads.delete(chapterID: chapterID)
        downloadItems.removeAll { $0.id == chapterID }
    }

    func refreshDownloadRecords() async {
        let records = await downloads.allRecords()
        for record in records {
            guard let index = downloadItems.firstIndex(where: { $0.id == record.chapterID }) else { continue }
            downloadItems[index].progress = record.progress
            downloadItems[index].state = record.state
        }
        downloadItems.removeAll { item in
            !records.contains { $0.chapterID == item.id } && item.state == .cancelled
        }
    }

    private func observeDownloads() async {
        for await record in await downloads.stateFeed() {
            if let index = downloadItems.firstIndex(where: { $0.id == record.chapterID }) {
                downloadItems[index].progress = record.progress
                downloadItems[index].state = record.state
            }
        }
    }

    // MARK: - Translation

    func translatePage(_ page: PageResource, from source: Language, to target: Language) async throws -> [TranslatedBubble] {
        let cacheKey = "\(page.index)-\(source.code)-\(target.code)-\(originKey(page.origin))"
        if let cached = bubbleCache[cacheKey] { return cached }

        let data: Data
        switch page.origin {
        case .remote(let url):
            (data, _) = try await URLSession.shared.data(from: url)
        case .localFile(let url):
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        }

        let service = PageTranslationService(recognizer: recognizer, translator: translator)
        let bubbles = try await service.translatePage(imageData: data, from: source, to: target)
        bubbleCache[cacheKey] = bubbles
        return bubbles
    }

    private func originKey(_ origin: PageResource.Origin) -> String {
        switch origin {
        case .remote(let url): return url.absoluteString
        case .localFile(let url): return url.path
        }
    }

    /// Round-trips a short string through the configured translator so the
    /// settings screen can prove the provider works.
    func testTranslation(_ text: String, from source: Language, to target: Language) async throws -> String {
        try await translator.translate(text, from: source, to: target)
    }

    func applyTranslationProvider() {
        UserDefaults.standard.set(translationProvider.rawValue, forKey: TranslationProvider.key)
        UserDefaults.standard.set(translationEndpoint, forKey: TranslationProvider.endpointKey)
        UserDefaults.standard.set(translationAPIKey, forKey: TranslationProvider.apiKeyKey)

        switch translationProvider {
        case .apple:
            #if canImport(Translation)
            translator = CachingTranslator(upstream: AppleTranslationTranslator())
            #else
            translator = IdentityTranslator()
            #endif
        case .remote:
            let url = URL(string: translationEndpoint) ?? URL(string: "https://libretranslate.com/translate")!
            let config = HTTPTextTranslator.Configuration.libreTranslate(url, apiKey: translationAPIKey.isEmpty ? nil : translationAPIKey)
            translator = CachingTranslator(upstream: HTTPTextTranslator(config: config, transport: URLSessionTransport()))
        }
    }
}

/// Placeholder recognizer for platforms without Vision.
struct NoOpTextRecognizer: ImageTextRecognizer {
    func recognizeText(in imageData: Data, preferredLanguages: [String]) async throws -> [RecognizedText] {
        throw TranslationError.unavailable
    }
}

enum DiscoverSection: String, CaseIterable, Identifiable {
    case popular, latest
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
