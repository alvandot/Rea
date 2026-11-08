import Foundation

/// AniList GraphQL tracker (implicit-grant OAuth, token persisted by the app).
public struct AniListTracker: TrackerService {
    public nonisolated let id = "anilist"
    public nonisolated let name = "AniList"

    private let tokens: any TokenProvider
    private let transport: any HTTPTransport
    private let endpoint = URL(string: "https://graphql.anilist.co")!

    public init(tokens: any TokenProvider, transport: any HTTPTransport = URLSessionTransport()) {
        self.tokens = tokens
        self.transport = transport
    }

    public var isAuthenticated: Bool {
        get async { ((try? await tokens.accessToken()) ?? nil) != nil }
    }

    public func search(_ query: String) async throws -> [TrackerSearchResult] {
        let query = """
        query ($search: String) {
          Page(perPage: 20) {
            media(search: $search, type: MANGA) {
              id
              title { romaji english }
              chapters
              coverImage { medium }
            }
          }
        }
        """
        let data = try await send(query: query, variables: ["search": query])
        let envelope = try JSONDecoder().decode(SearchEnvelope.self, from: data)
        return envelope.data.page.media.map {
            TrackerSearchResult(
                id: String($0.id),
                title: $0.title.english ?? $0.title.romaji ?? "Untitled",
                totalChapters: $0.chapters,
                coverURL: $0.coverImage?.medium.flatMap(URL.init(string:))
            )
        }
    }

    public func list(status: TrackerStatus?) async throws -> [TrackerEntry] {
        let query = """
        query {
          Viewer {
            mangaList {
              entries {
                mediaId
                status
                progress
                media { title { romaji english } }
              }
            }
          }
        }
        """
        let data = try await send(query: query, variables: [:])
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        return envelope.data.viewer.mangaList.entries.compactMap { entry in
            let mapped = Self.mapStatus(entry.status)
            if let status, mapped != status { return nil }
            return TrackerEntry(
                id: String(entry.mediaId),
                remoteID: String(entry.mediaId),
                title: entry.media.title.english ?? entry.media.title.romaji ?? "",
                progress: entry.progress ?? 0,
                status: mapped
            )
        }
    }

    public func updateProgress(remoteID: String, chapters: Int, status: TrackerStatus?) async throws -> TrackerEntry {
        guard let mediaID = Int(remoteID) else { throw TrackerError.parse("bad media id") }
        let query = """
        mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus) {
          SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status) {
            mediaId
            progress
            status
          }
        }
        """
        let data = try await send(query: query, variables: [
            "mediaId": mediaID,
            "progress": chapters,
            "status": Self.anilistStatus(status ?? .reading)
        ])
        let envelope = try JSONDecoder().decode(SaveEnvelope.self, from: data)
        let entry = envelope.data.saveMediaListEntry
        return TrackerEntry(
            id: String(entry.mediaId),
            remoteID: String(entry.mediaId),
            title: "",
            progress: entry.progress ?? chapters,
            status: Self.mapStatus(entry.status)
        )
    }

    public func deleteEntry(remoteID: String) async throws {
        guard let mediaID = Int(remoteID) else { throw TrackerError.parse("bad media id") }
        let query = """
        mutation ($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }
        """
        _ = try await send(query: query, variables: ["id": mediaID])
    }

    // MARK: - Networking

    private func send(query: String, variables: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = (try? await tokens.accessToken()) ?? nil {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": variables
        ])
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            switch response.statusCode {
            case 401: throw TrackerError.unauthorized
            case 404: throw TrackerError.notFound
            default: throw TrackerError.network("HTTP \(response.statusCode)")
            }
        }
        return data
    }

    private static func mapStatus(_ raw: String) -> TrackerStatus {
        switch raw {
        case "CURRENT": return .reading
        case "COMPLETED": return .completed
        case "PAUSED": return .onHold
        case "DROPPED": return .dropped
        case "PLANNING": return .planToRead
        default: return .reading
        }
    }

    private static func anilistStatus(_ status: TrackerStatus) -> String {
        switch status {
        case .reading, .watching: return "CURRENT"
        case .completed: return "COMPLETED"
        case .onHold: return "PAUSED"
        case .dropped: return "DROPPED"
        case .planToRead: return "PLANNING"
        }
    }

    // MARK: - DTOs

    private struct Title: Decodable { let romaji: String?; let english: String? }

    private struct SearchEnvelope: Decodable {
        let data: Data
        struct Data: Decodable { let page: Page }
        struct Page: Decodable { let media: [Media] }
        struct Media: Decodable {
            let id: Int
            let title: Title
            let chapters: Int?
            let coverImage: Cover?
            struct Cover: Decodable { let medium: String? }
        }
    }

    private struct ListEnvelope: Decodable {
        let data: Data
        struct Data: Decodable { let viewer: Viewer }
        struct Viewer: Decodable { let mangaList: MangaList }
        struct MangaList: Decodable { let entries: [Entry] }
        struct Entry: Decodable {
            let mediaId: Int
            let status: String
            let progress: Int?
            let media: Media
            struct Media: Decodable { let title: Title }
        }
    }

    private struct SaveEnvelope: Decodable {
        let data: Data
        struct Data: Decodable { let saveMediaListEntry: Entry }
        struct Entry: Decodable {
            let mediaId: Int
            let progress: Int?
            let status: String
        }
    }
}
