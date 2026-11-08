import Foundation
#if canImport(CoreData)
import CoreData

/// Programmatic Core Data model (no .xcdatamodeld resource needed).
public enum CoreDataModel {
    public static func make() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let series = entity(
            name: "SeriesEntity",
            attributes: [
                .init(name: "id", type: .UUIDAttributeType, optional: false),
                .init(name: "sourceID", type: .stringAttributeType, optional: false),
                .init(name: "remoteID", type: .stringAttributeType, optional: false),
                .init(name: "title", type: .stringAttributeType, optional: false),
                .init(name: "author", type: .stringAttributeType, optional: true),
                .init(name: "artist", type: .stringAttributeType, optional: true),
                .init(name: "summary", type: .stringAttributeType, optional: true),
                .init(name: "coverURL", type: .stringAttributeType, optional: true),
                .init(name: "status", type: .stringAttributeType, optional: false),
                .init(name: "rating", type: .stringAttributeType, optional: false),
                .init(name: "categories", type: .binaryDataAttributeType, optional: true),
                .init(name: "lastUpdated", type: .dateAttributeType, optional: true),
                .init(name: "isFavorite", type: .booleanAttributeType, optional: false)
            ],
            className: "SeriesEntity"
        )

        let chapter = entity(
            name: "ChapterEntity",
            attributes: [
                .init(name: "id", type: .UUIDAttributeType, optional: false),
                .init(name: "seriesID", type: .UUIDAttributeType, optional: false),
                .init(name: "sourceID", type: .stringAttributeType, optional: false),
                .init(name: "remoteID", type: .stringAttributeType, optional: false),
                .init(name: "name", type: .stringAttributeType, optional: false),
                .init(name: "number", type: .doubleAttributeType, optional: false),
                .init(name: "uploadedAt", type: .dateAttributeType, optional: true),
                .init(name: "pageCount", type: .integer32AttributeType, optional: true),
                .init(name: "isRead", type: .booleanAttributeType, optional: false),
                .init(name: "isBookmarked", type: .booleanAttributeType, optional: false)
            ],
            className: "ChapterEntity"
        )

        let progress = entity(
            name: "ProgressEntity",
            attributes: [
                .init(name: "chapterID", type: .UUIDAttributeType, optional: false),
                .init(name: "page", type: .integer32AttributeType, optional: false),
                .init(name: "scrollOffset", type: .doubleAttributeType, optional: false),
                .init(name: "updatedAt", type: .dateAttributeType, optional: false)
            ],
            className: "ProgressEntity"
        )

        model.entities = [series, chapter, progress]
        return model
    }

    private static func entity(
        name: String,
        attributes: [NSAttributeDescription],
        className: String
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = className
        entity.properties = attributes
        return entity
    }
}

@objc(SeriesEntity)
public final class SeriesEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var sourceID: String?
    @NSManaged public var remoteID: String?
    @NSManaged public var title: String?
    @NSManaged public var author: String?
    @NSManaged public var artist: String?
    @NSManaged public var summary: String?
    @NSManaged public var coverURL: String?
    @NSManaged public var status: String?
    @NSManaged public var rating: String?
    @NSManaged public var categories: Data?
    @NSManaged public var lastUpdated: Date?
    @NSManaged public var isFavorite: Bool
}

@objc(ChapterEntity)
public final class ChapterEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var seriesID: UUID?
    @NSManaged public var sourceID: String?
    @NSManaged public var remoteID: String?
    @NSManaged public var name: String?
    @NSManaged public var number: Double
    @NSManaged public var uploadedAt: Date?
    @NSManaged public var pageCount: Int32
    @NSManaged public var isRead: Bool
    @NSManaged public var isBookmarked: Bool
}

@objc(ProgressEntity)
public final class ProgressEntity: NSManagedObject {
    @NSManaged public var chapterID: UUID?
    @NSManaged public var page: Int32
    @NSManaged public var scrollOffset: Double
    @NSManaged public var updatedAt: Date?
}
#endif
