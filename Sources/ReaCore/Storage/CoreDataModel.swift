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
                .init(name: "id", type: NSAttributeType.UUIDAttributeType, optional: false),
                .init(name: "sourceID", type: NSAttributeType.stringAttributeType, optional: false),
                .init(name: "remoteID", type: NSAttributeType.stringAttributeType, optional: false),
                .init(name: "title", type: NSAttributeType.stringAttributeType, optional: false),
                .init(name: "author", type: NSAttributeType.stringAttributeType, optional: true),
                .init(name: "artist", type: NSAttributeType.stringAttributeType, optional: true),
                .init(name: "summary", type: NSAttributeType.stringAttributeType, optional: true),
                .init(name: "coverURL", type: NSAttributeType.stringAttributeType, optional: true),
                .init(name: "status", type: NSAttributeType.stringAttributeType, optional: false),
                .init(name: "rating", type: NSAttributeType.stringAttributeType, optional: false),
                .init(name: "categories", type: NSAttributeType.binaryDataAttributeType, optional: true),
                .init(name: "lastUpdated", type: NSAttributeType.dateAttributeType, optional: true),
                .init(name: "isFavorite", type: NSAttributeType.booleanAttributeType, optional: false)
            ],
            className: "SeriesEntity"
        )

        let chapter = entity(
            name: "ChapterEntity",
            attributes: [
                .init(name: "id", type: NSAttributeType.UUIDAttributeType, optional: false),
                .init(name: "seriesID", type: NSAttributeType.UUIDAttributeType, optional: false),
                .init(name: "sourceID", type: NSAttributeType.stringAttributeType, optional: false),
                .init(name: "remoteID", type: NSAttributeType.stringAttributeType, optional: false),
                .init(name: "name", type: NSAttributeType.stringAttributeType, optional: false),
                .init(name: "number", type: NSAttributeType.doubleAttributeType, optional: false),
                .init(name: "uploadedAt", type: NSAttributeType.dateAttributeType, optional: true),
                .init(name: "pageCount", type: NSAttributeType.integer32AttributeType, optional: true),
                .init(name: "isRead", type: NSAttributeType.booleanAttributeType, optional: false),
                .init(name: "isBookmarked", type: NSAttributeType.booleanAttributeType, optional: false)
            ],
            className: "ChapterEntity"
        )

        let progress = entity(
            name: "ProgressEntity",
            attributes: [
                .init(name: "chapterID", type: NSAttributeType.UUIDAttributeType, optional: false),
                .init(name: "page", type: NSAttributeType.integer32AttributeType, optional: false),
                .init(name: "scrollOffset", type: NSAttributeType.doubleAttributeType, optional: false),
                .init(name: "updatedAt", type: NSAttributeType.dateAttributeType, optional: false)
            ],
            className: "ProgressEntity"
        )

        model.entities = [series, chapter, progress]
        return model
    }

    /// Attribute spec used by `entity(...)`. Type is `NSAttributeType` rather
    /// than an inference-through-`init` chain because Swift cannot resolve
    /// leading-dot members of a nested enum through a synthesized initializer.
    public struct Attribute {
        let name: String
        let type: NSAttributeType
        let optional: Bool

        init(name: String, type: NSAttributeType, optional: Bool) {
            self.name = name
            self.type = type
            self.optional = optional
        }
    }

    private static func entity(
        name: String,
        attributes: [Attribute],
        className: String
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = className
        entity.properties = attributes.map { spec in
            let attribute = NSAttributeDescription()
            attribute.name = spec.name
            attribute.attributeType = spec.type
            attribute.isOptional = spec.optional
            return attribute
        }
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
