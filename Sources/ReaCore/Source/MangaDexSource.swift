import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal MangaDex client implementing `ContentSource`.
public actor MangaDexSource: ContentSource {
    public nonisolated let id = "mangadex"
    public nonisolated let name = "MangaDex"
    public nonisolated let language: String

    private let baseURL = URL(string: "https://api.mangadex.org")!
    private let session: URLSession
    private var accessToken: String?

    public init(language: String = "en", session: URLSession = .shared) {
        self.language = language
        self.session = session
    }

    public func setAccessToken(_ token: String?) { accessToken = token }

    // MARK: - ContentSource

    public func popular(page: Int) async throws -> PagedResult<Series> {
        try await searchPage(page: page, query: nil, popular: true)
    }

    public func latest(page: Int) async throws -> PagedResult<Series> {
        try await searchPage(page: page, query: nil, popular: false)
    }

    public func search(_ query: String, page: Int) async throws -> PagedResult<Series> {
        try await searchPage(page: page, query: query, popular: false)
    }

    public func series(remoteID: String) async throws -> Series {
        let req = try request(path: "/manga/\(remoteID)", query: [
            URLQueryItem(name: "includes[]", value: "cover_art")
        ])
        let (data, _) = try await session.data(for: req)
        let envelope = try JSONDecoder.mangaDex.decode(MangaEnvelope.self, from: data)
        guard let manga = envelope.data else { throw SourceError.notFound }
        return mapSeries(manga)
    }

    public func chapters(seriesRemoteID: String) async throws -> [Chapter] {
        var all: [Chapter] = []
        var offset = 0
        let limit = 100
        while true {
            let req = try request(path: "/manga/\(seriesRemoteID)/feed", query: [
                URLQueryItem(name: "translatedLanguage[]", value: language),
                URLQueryItem(name: "order[chapter]", value: "asc"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "includes[]", value: "scanlation_group")
            ])
            let (data, _) = try await session.data(for: req)
            let envelope = try JSONDecoder.mangaDex.decode(ChapterEnvelope.self, from: data)
            if envelope.data.isEmpty { break }
            all.append(contentsOf: envelope.data.compactMap { mapChapter($0, seriesRemoteID: seriesRemoteID) })
            offset += limit
            if envelope.data.count < limit { break }
        }
        return all
    }

    public func pages(chapterRemoteID: String) async throws -> [PageResource] {
        let req = try request(path: "/at-home/server/\(chapterRemoteID)", query: [])
        let (data, _) = try await session.data(for: req)
        let home = try JSONDecoder.mangaDex.decode(AtHomeResponse.self, from: data)
        let base = "\(home.baseUrl)/\(home.chapter.hash)"
        return home.chapter.data.enumerated().compactMap { idx, filename in
            URL(string: "\(base)/\(filename)").map { PageResource(origin: .remote($0), index: idx) }
        }
    }

    // MARK: - Internals

    private func searchPage(page: Int, query: String?, popular: Bool) async throws -> PagedResult<Series> {
        let limit = 40
        let offset = max(0, (page - 1) * limit)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "includes[]", value: "cover_art"),
            URLQueryItem(name: "contentRating[]", value: "safe"),
            URLQueryItem(name: "contentRating[]", value: "suggestive")
        ]
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "title", value: query))
        }
        items.append(URLQueryItem(
            name: "order[\(popular ? "followedCount" : "latestUploadedChapter")]",
            value: "desc"
        ))
        let req = try request(path: "/manga", query: items)
        let (data, _) = try await session.data(for: req)
        let envelope = try JSONDecoder.mangaDex.decode(MangaListEnvelope.self, from: data)
        let series = envelope.data.map(mapSeries)
        return PagedResult(items: series, hasNext: offset + series.count < envelope.total)
    }

    private func request(path: String, query: [URLQueryItem]) throws -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        comps?.queryItems = query
        guard let url = comps?.url else { throw SourceError.parse("bad url") }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private func mapSeries(_ manga: MangaDexMangaDTO) -> Series {
        let attrs = manga.attributes
        let title = attrs.title["en"] ?? attrs.title.values.first ?? "Untitled"
        let cover = manga.relationships
            .first(where: { $0.type == "cover_art" })?
            .attributes?.fileName
            .flatMap { URL(string: "https://uploads.mangadex.org/covers/\(manga.id)/\($0).256.jpg") }
        let author = manga.relationships
            .first(where: { $0.type == "author" })?
            .attributes?.name
        let artist = manga.relationships
            .first(where: { $0.type == "artist" })?
            .attributes?.name
        let categories = attrs.tags.compactMap { $0.attributes.name["en"] ?? $0.attributes.name.values.first }
        return Series(
            id: StableID.uuid(sourceID: id, remoteID: manga.id),
            sourceID: id,
            remoteID: manga.id,
            title: title,
            author: author,
            artist: artist,
            summary: attrs.description["en"] ?? attrs.description.values.first,
            coverURL: cover,
            status: Self.readingStatus(from: attrs.status),
            rating: Self.contentRating(from: attrs.contentRating),
            categories: categories
        )
    }

    private static func readingStatus(from raw: String?) -> ReadingStatus {
        switch raw {
        case "ongoing": return .reading
        case "completed": return .completed
        case "hiatus": return .onHold
        case "cancelled": return .dropped
        default: return .planToRead
        }
    }

    private static func contentRating(from raw: String?) -> ContentRating {
        switch raw {
        case "erotica": return .erotica
        case "pornographic": return .pornographic
        case "suggestive": return .suggestive
        default: return .safe
        }
    }

    private func mapChapter(_ chapter: MangaDexChapterDTO, seriesRemoteID: String) -> Chapter? {
        let num = chapter.attributes.chapter.flatMap(Double.init) ?? 0
        return Chapter(
            id: StableID.uuid(sourceID: id, remoteID: chapter.id),
            seriesID: StableID.uuid(sourceID: id, remoteID: seriesRemoteID),
            sourceID: id,
            remoteID: chapter.id,
            name: chapter.attributes.title ?? "Chapter \(chapter.attributes.chapter ?? "?")",
            number: num,
            uploadedAt: chapter.attributes.publishAt
        )
    }
}

// MARK: - DTOs

struct MangaEnvelope: Decodable {
    let data: MangaDexMangaDTO?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decodeIfPresent(MangaDexMangaDTO.self, forKey: .data)
    }

    enum CodingKeys: String, CodingKey { case data }
}

struct MangaListEnvelope: Decodable {
    let data: [MangaDexMangaDTO]
    let total: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decodeIfPresent([MangaDexMangaDTO].self, forKey: .data) ?? []
        // The list endpoint reports `total` one level up, in `Meta`.
        let meta = try? c.decodeIfPresent(Meta.self, forKey: .meta)
        total = meta?.total ?? data.count
    }

    enum CodingKeys: String, CodingKey { case data, meta }

    struct Meta: Decodable {
        let total: Int?
    }
}

struct MangaDexMangaDTO: Decodable {
    let id: String
    let attributes: Attributes
    let relationships: [Relationship]

    struct Attributes: Decodable {
        let title: [String: String]
        let description: [String: String]
        let status: String?
        let year: Int?
        let contentRating: String?
        let tags: [Tag]

        enum CodingKeys: String, CodingKey {
            case title, description, status, year, contentRating, tags
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = (try? c.decode([String: String].self, forKey: .title)) ?? [:]
            description = (try? c.decode([String: String].self, forKey: .description)) ?? [:]
            status = try? c.decodeIfPresent(String.self, forKey: .status)
            year = try? c.decodeIfPresent(Int.self, forKey: .year)
            contentRating = try? c.decodeIfPresent(String.self, forKey: .contentRating)
            tags = (try? c.decodeIfPresent([Tag].self, forKey: .tags)) ?? []
        }

        struct Tag: Decodable {
            let attributes: Attributes
            struct Attributes: Decodable {
                let name: [String: String]
            }
        }
    }

    struct Relationship: Decodable {
        let type: String
        let attributes: Attributes?

        struct Attributes: Decodable {
            /// `cover_art` rows carry `fileName`.
            let fileName: String?
            /// `author` / `artist` rows carry `name`.
            let name: String?

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                fileName = try? c.decodeIfPresent(String.self, forKey: .fileName)
                name = try? c.decodeIfPresent(String.self, forKey: .name)
            }

            enum CodingKeys: String, CodingKey { case fileName, name }
        }
    }
}

struct ChapterEnvelope: Decodable {
    let data: [MangaDexChapterDTO]
}

struct MangaDexChapterDTO: Decodable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let chapter: String?
        let title: String?
        let publishAt: Date?
    }
}

struct AtHomeResponse: Decodable {
    let baseUrl: String
    let chapter: Chapter

    struct Chapter: Decodable {
        let hash: String
        let data: [String]
    }
}

extension JSONDecoder {
    static var mangaDex: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(string)")
        }
        return decoder
    }
}
