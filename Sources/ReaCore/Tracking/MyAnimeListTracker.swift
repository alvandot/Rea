import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// MyAnimeList REST v2 manga list tracker.
public struct MyAnimeListTracker: TrackerService {
    public nonisolated let id = "myanimelist"
    public nonisolated let name = "MyAnimeList"

    private let tokens: any TokenProvider
    private let transport: any HTTPTransport
    private let baseURL = URL(string: "https://api.myanimelist.net/v2")!

    public init(tokens: any TokenProvider, transport: any HTTPTransport = URLSessionTransport()) {
        self.tokens = tokens
        self.transport = transport
    }

    public var isAuthenticated: Bool {
        get async { ((try? await tokens.accessToken()) ?? nil) != nil }
    }

    public func search(_ query: String) async throws -> [TrackerSearchResult] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("manga"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "fields", value: "num_chapters,main_picture")
        ]
        let data = try await get(comps.url!)
        let envelope = try JSONDecoder().decode(SearchEnvelope.self, from: data)
        return envelope.data.map {
            TrackerSearchResult(
                id: String($0.node.id),
                title: $0.node.title,
                totalChapters: $0.node.numChapters,
                coverURL: $0.node.mainPicture?.medium.flatMap(URL.init(string:))
            )
        }
    }

    public func list(status: TrackerStatus?) async throws -> [TrackerEntry] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("users/@me/mangalist"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "fields", value: "list_status"),
            URLQueryItem(name: "limit", value: "1000")
        ]
        let data = try await get(comps.url!)
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        return envelope.data.compactMap { item in
            guard let listStatus = item.listStatus else { return nil }
            let mapped = Self.mapStatus(listStatus.status)
            if let status, mapped != status { return nil }
            return TrackerEntry(
                id: String(item.node.id),
                remoteID: String(item.node.id),
                title: item.node.title,
                progress: listStatus.numChaptersRead ?? 0,
                status: mapped
            )
        }
    }

    public func updateProgress(remoteID: String, chapters: Int, status: TrackerStatus?) async throws -> TrackerEntry {
        let url = baseURL.appendingPathComponent("manga/\(remoteID)/my_list_status")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let malStatus = Self.malStatus(status ?? .reading)
        var form = "status=\(malStatus)&num_chapters_read=\(chapters)"
        form += "&updated_at=\(ISO8601DateFormatter().string(from: .now).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        request.httpBody = form.data(using: .utf8)

        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(for: response.statusCode) }
        let body = try JSONDecoder().decode(UpdateResponse.self, from: data)
        return TrackerEntry(
            id: remoteID,
            remoteID: remoteID,
            title: "",
            progress: body.numChaptersRead ?? chapters,
            status: Self.mapStatus(body.status)
        )
    }

    public func deleteEntry(remoteID: String) async throws {
        let url = baseURL.appendingPathComponent("manga/\(remoteID)/my_list_status")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(for: response.statusCode) }
    }

    // MARK: - Networking

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(for: response.statusCode) }
        return data
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let token = (try? await tokens.accessToken()) ?? nil else {
            throw TrackerError.notAuthenticated
        }
        var authorized = request
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        authorized.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await transport.send(authorized)
    }

    private static func error(for status: Int) -> TrackerError {
        switch status {
        case 401: return .unauthorized
        case 404: return .notFound
        default: return .network("HTTP \(status)")
        }
    }

    private static func mapStatus(_ raw: String) -> TrackerStatus {
        switch raw {
        case "reading": return .reading
        case "completed": return .completed
        case "on_hold": return .onHold
        case "dropped": return .dropped
        case "plan_to_read": return .planToRead
        default: return .reading
        }
    }

    private static func malStatus(_ status: TrackerStatus) -> String {
        switch status {
        case .reading, .watching: return "reading"
        case .completed: return "completed"
        case .onHold: return "on_hold"
        case .dropped: return "dropped"
        case .planToRead: return "plan_to_read"
        }
    }

    // MARK: - DTOs

    private struct SearchEnvelope: Decodable {
        let data: [Item]
        struct Item: Decodable {
            let node: Node
            struct Node: Decodable {
                let id: Int
                let title: String
                let numChapters: Int?
                let mainPicture: Picture?
                struct Picture: Decodable { let medium: String? }
            }
        }
    }

    private struct ListEnvelope: Decodable {
        let data: [Item]
        struct Item: Decodable {
            let node: Node
            let listStatus: ListStatus?
            struct Node: Decodable { let id: Int; let title: String }
            struct ListStatus: Decodable {
                let status: String
                let numChaptersRead: Int?
            }
        }
    }

    private struct UpdateResponse: Decodable {
        let status: String
        let numChaptersRead: Int?
    }
}
