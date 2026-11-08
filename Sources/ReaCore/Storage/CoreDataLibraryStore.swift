import Foundation
#if canImport(CoreData)
import CoreData

/// Core Data implementation of `LibraryStore`. Uses `NSPersistentCloudKitContainer`
/// so the same store syncs through iCloud when the entitlement and container are
/// present, and falls back to a local store otherwise.
public actor CoreDataLibraryStore: LibraryStore {
    public enum Configuration: Sendable {
        case cloudKit
        case local
        case preview
    }

    private let container: NSPersistentContainer

    public init(configuration: Configuration = .local) throws {
        let model = CoreDataModel.make()
        switch configuration {
        case .preview:
            let container = NSPersistentContainer(name: "ReaPreview", managedObjectModel: model)
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
            self.container = container
        case .local:
            self.container = NSPersistentContainer(name: "Rea", managedObjectModel: model)
        case .cloudKit:
            self.container = NSPersistentCloudKitContainer(name: "Rea", managedObjectModel: model)
        }

        if configuration != .preview {
            for description in container.persistentStoreDescriptions {
                description.shouldMigrateStoreAutomatically = true
                description.shouldInferMappingModelAutomatically = true
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            }
        }

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let loadError { throw loadError }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Series

    public func loadSeries() async throws -> [Series] {
        try await perform { context in
            let request = NSFetchRequest<SeriesEntity>(entityName: "SeriesEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
            return try context.fetch(request).compactMap(Self.toModel)
        }
    }

    public func upsert(_ series: [Series]) async throws {
        try await perform { context in
            for item in series {
                let entity = try Self.fetchSeries(id: item.id, in: context) ?? SeriesEntity(context: context)
                Self.apply(item, to: entity)
            }
            try Self.saveIfNeeded(context)
        }
    }

    public func delete(seriesID: UUID) async throws {
        try await perform { context in
            let seriesRequest = NSFetchRequest<SeriesEntity>(entityName: "SeriesEntity")
            seriesRequest.predicate = NSPredicate(format: "id == %@", seriesID as CVarArg)
            for entity in try context.fetch(seriesRequest) { context.delete(entity) }

            let chapterRequest = NSFetchRequest<ChapterEntity>(entityName: "ChapterEntity")
            chapterRequest.predicate = NSPredicate(format: "seriesID == %@", seriesID as CVarArg)
            let chapters = try context.fetch(chapterRequest)
            let chapterIDs = chapters.compactMap(\.id)
            for chapter in chapters { context.delete(chapter) }

            if !chapterIDs.isEmpty {
                let progressRequest = NSFetchRequest<ProgressEntity>(entityName: "ProgressEntity")
                progressRequest.predicate = NSPredicate(format: "chapterID IN %@", chapterIDs)
                for progress in try context.fetch(progressRequest) { context.delete(progress) }
            }
            try Self.saveIfNeeded(context)
        }
    }

    // MARK: - Chapters

    public func chapters(for seriesID: UUID) async throws -> [Chapter] {
        try await perform { context in
            let request = NSFetchRequest<ChapterEntity>(entityName: "ChapterEntity")
            request.predicate = NSPredicate(format: "seriesID == %@", seriesID as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "number", ascending: true)]
            return try context.fetch(request).compactMap(Self.toModel)
        }
    }

    public func replaceChapters(for seriesID: UUID, with chapters: [Chapter]) async throws {
        try await perform { context in
            let request = NSFetchRequest<ChapterEntity>(entityName: "ChapterEntity")
            request.predicate = NSPredicate(format: "seriesID == %@", seriesID as CVarArg)
            let existing = try context.fetch(request)
            var readState: [String: (Bool, Bool)] = [:]
            for entity in existing {
                if let remoteID = entity.remoteID {
                    readState[remoteID] = (entity.isRead, entity.isBookmarked)
                }
                context.delete(entity)
            }

            for var chapter in chapters {
                if let flags = readState[chapter.remoteID] {
                    chapter.isRead = flags.0
                    chapter.isBookmarked = flags.1
                }
                let entity = ChapterEntity(context: context)
                Self.apply(chapter, to: entity)
            }
            try Self.saveIfNeeded(context)
        }
    }

    public func setChapterRead(_ chapterID: UUID, read: Bool) async throws {
        try await perform { context in
            let request = NSFetchRequest<ChapterEntity>(entityName: "ChapterEntity")
            request.predicate = NSPredicate(format: "id == %@", chapterID as CVarArg)
            guard let entity = try context.fetch(request).first else { return }
            entity.isRead = read
            try Self.saveIfNeeded(context)
        }
    }

    // MARK: - Progress

    public func progress(for chapterID: UUID) async throws -> ReadingProgress? {
        try await perform { context in
            let request = NSFetchRequest<ProgressEntity>(entityName: "ProgressEntity")
            request.predicate = NSPredicate(format: "chapterID == %@", chapterID as CVarArg)
            return try context.fetch(request).first.map(Self.toModel)
        }
    }

    public func saveProgress(_ progress: ReadingProgress) async throws {
        try await perform { context in
            let request = NSFetchRequest<ProgressEntity>(entityName: "ProgressEntity")
            request.predicate = NSPredicate(format: "chapterID == %@", progress.chapterID as CVarArg)
            if let existing = try context.fetch(request).first,
               let updated = existing.updatedAt,
               updated > progress.updatedAt {
                return   // last-write-wins
            }
            let entity = try context.fetch(request).first ?? ProgressEntity(context: context)
            entity.chapterID = progress.chapterID
            entity.page = Int32(progress.page)
            entity.scrollOffset = progress.scrollOffset
            entity.updatedAt = progress.updatedAt
            try Self.saveIfNeeded(context)
        }
    }

    // MARK: - Helpers

    private func perform<T>(_ work: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do { continuation.resume(returning: try work(context)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func fetchSeries(id: UUID, in context: NSManagedObjectContext) throws -> SeriesEntity? {
        let request = NSFetchRequest<SeriesEntity>(entityName: "SeriesEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private static func saveIfNeeded(_ context: NSManagedObjectContext) throws {
        if context.hasChanges { try context.save() }
    }

    private static func apply(_ series: Series, to entity: SeriesEntity) {
        entity.id = series.id
        entity.sourceID = series.sourceID
        entity.remoteID = series.remoteID
        entity.title = series.title
        entity.author = series.author
        entity.artist = series.artist
        entity.summary = series.summary
        entity.coverURL = series.coverURL?.absoluteString
        entity.status = series.status.rawValue
        entity.rating = series.rating.rawValue
        entity.categories = try? JSONEncoder().encode(series.categories)
        entity.lastUpdated = series.lastUpdated
        entity.isFavorite = series.isFavorite
    }

    private static func apply(_ chapter: Chapter, to entity: ChapterEntity) {
        entity.id = chapter.id
        entity.seriesID = chapter.seriesID
        entity.sourceID = chapter.sourceID
        entity.remoteID = chapter.remoteID
        entity.name = chapter.name
        entity.number = chapter.number
        entity.uploadedAt = chapter.uploadedAt
        entity.pageCount = Int32(chapter.pageCount ?? 0)
        entity.isRead = chapter.isRead
        entity.isBookmarked = chapter.isBookmarked
    }

    private static func toModel(_ entity: SeriesEntity) -> Series? {
        guard let id = entity.id,
              let sourceID = entity.sourceID,
              let remoteID = entity.remoteID,
              let title = entity.title else { return nil }
        let categories = entity.categories.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return Series(
            id: id,
            sourceID: sourceID,
            remoteID: remoteID,
            title: title,
            author: entity.author,
            artist: entity.artist,
            summary: entity.summary,
            coverURL: entity.coverURL.flatMap(URL.init(string:)),
            status: ReadingStatus(rawValue: entity.status ?? "") ?? .planToRead,
            rating: ContentRating(rawValue: entity.rating ?? "") ?? .safe,
            categories: categories,
            lastUpdated: entity.lastUpdated,
            isFavorite: entity.isFavorite
        )
    }

    private static func toModel(_ entity: ChapterEntity) -> Chapter? {
        guard let id = entity.id,
              let seriesID = entity.seriesID,
              let sourceID = entity.sourceID,
              let remoteID = entity.remoteID,
              let name = entity.name else { return nil }
        return Chapter(
            id: id,
            seriesID: seriesID,
            sourceID: sourceID,
            remoteID: remoteID,
            name: name,
            number: entity.number,
            uploadedAt: entity.uploadedAt,
            pageCount: entity.pageCount > 0 ? Int(entity.pageCount) : nil,
            isRead: entity.isRead,
            isBookmarked: entity.isBookmarked
        )
    }

    private static func toModel(_ entity: ProgressEntity) -> ReadingProgress? {
        guard let chapterID = entity.chapterID else { return nil }
        return ReadingProgress(
            chapterID: chapterID,
            page: Int(entity.page),
            scrollOffset: entity.scrollOffset,
            updatedAt: entity.updatedAt ?? .distantPast
        )
    }
}
#endif
