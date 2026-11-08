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

    private func mapSeries(_ manga: MangaEntity) -> Series {
        let title = manga.attributes.title["en"]
            ?? manga.attributes.title.values.first
            ?? "Untitled"
        let cover = manga.relationships
            .first(where: { $0.type == "cover_art" })?
            .attributes?.fileName
            .flatMap { URL(string: "https://uploads.mangadex.org/covers/\(manga.id)/\($0)") }
        return Series(
            id: StableID.uuid(sourceID: id, remoteID: manga.id),
            sourceID: id,
            remoteID: manga.id,
            title: title,
            author: manga.attributes.authorName,
            artist: manga.attributes.artistName,
            summary: manga.attributes.description["en"],
            coverURL: cover,
            lastUpdated: manga.attributes.updatedAt
        )
    }

    private func mapChapter(_ chapter: ChapterEntity, seriesRemoteID: String) -> Chapter? {
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
    let data: MangaEntity?
    let total: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decodeIfPresent(MangaEntity.self, forKey: .data)
        total = try? c.decode(Int.self, forKey: .total)
    }
    enum CodingKeys: String, CodingKey { case data, total }
}

struct MangaListEnvelope: Decodable {
    let data: [MangaEntity]
    let total: Int
}

struct MangaEntity: Decodable {
    let id: String
    let attributes: Attributes
    let relationships: [Relationship]

    struct Attributes: Decodable {
        let title: [String: String]
        let description: [String: String]
        let authorName: String?
        let artistName: String?
        let updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case title, description, updatedAt
            case authorName = "authorName"
            case artistName = "artistName"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = (try? c.decode([String: String].self, forKey: .title)) ?? [:]
            description = (try? c.decode([String: String].self, forKey: .description)) ?? [:]
            authorName = try? c.decodeIfPresent(String.self, forKey: .authorName)
            artistName = try? c.decodeIfPresent(String.self, forKey: .artistName)
            updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        }
    }

    struct Relationship: Decodable {
        let type: String
        let attributes: Attributes?
        struct Attributes: Decodable { let fileName: String? }
    }
}

struct ChapterEnvelope: Decodable {
    let data: [ChapterEntity]
}

struct ChapterEntity: Decodable {
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
