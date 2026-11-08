import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

/// PKCE verifier/challenge pair (RFC 7636, S256).
public struct PKCEChallenge: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
    public let method: String

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.s256(verifier)
        self.method = "S256"
    }

    public static func random() -> PKCEChallenge {
        var bytes = [UInt8](repeating: 0, count: 32)
        #if canImport(Security)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        #else
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        #endif
        return PKCEChallenge(verifier: base64URL(Data(bytes)))
    }

    static func s256(_ verifier: String) -> String {
        #if canImport(CryptoKit)
        return base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        #else
        return base64URL(Data(verifier.utf8))
        #endif
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum OAuthError: Error, Equatable, Sendable {
    case malformedCallback
    case authorizationDenied(String)
    case stateMismatch
    case noCredentials
    case tokenExchangeFailed
    case cancelled
    case unsupported
}

public enum OAuthCallback: Sendable, Equatable {
    case code(String)
    case token(accessToken: String, refreshToken: String?, expiresIn: Int?)
}

public struct OAuthTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

/// Builds an authorization URL and parses the redirect for OAuth 2.0 code flow
/// (PKCE) or implicit flow (fragment tokens).
public struct OAuthConfiguration: Sendable {
    public enum Flow: Sendable {
        case authorizationCode
        case implicit
    }

    public var authorizeURL: URL
    public var tokenURL: URL?
    public var clientID: String
    public var redirectURI: String
    public var scopes: [String]
    public var flow: Flow
    public var extraAuthorizeParams: [String: String]

    public init(
        authorizeURL: URL,
        tokenURL: URL? = nil,
        clientID: String,
        redirectURI: String,
        scopes: [String],
        flow: Flow,
        extraAuthorizeParams: [String: String] = [:]
    ) {
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.flow = flow
        self.extraAuthorizeParams = extraAuthorizeParams
    }

    public func authorizationURL(state: String, pkce: PKCEChallenge?) -> URL {
        var comps = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: flow == .authorizationCode ? "code" : "token"),
            .init(name: "state", value: state)
        ]
        if !scopes.isEmpty { items.append(.init(name: "scope", value: scopes.joined(separator: " "))) }
        if let pkce {
            items.append(.init(name: "code_challenge", value: pkce.challenge))
            items.append(.init(name: "code_challenge_method", value: pkce.method))
        }
        items.append(contentsOf: extraAuthorizeParams.map { URLQueryItem(name: $0.key, value: $0.value) })
        comps.queryItems = items
        return comps.url!
    }

    public func parseCallback(_ url: URL, expectedState: String) throws -> OAuthCallback {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OAuthError.malformedCallback
        }
        var params: [String: String] = [:]
        for item in comps.queryItems ?? [] { params[item.name] = item.value }
        if let fragment = comps.fragment {
            for pair in fragment.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 { params[String(parts[0])] = String(parts[1]) }
            }
        }

        if let error = params["error"] { throw OAuthError.authorizationDenied(error) }
        if let state = params["state"], state != expectedState { throw OAuthError.stateMismatch }
        if let code = params["code"] { return .code(code) }
        if let token = params["access_token"] {
            return .token(
                accessToken: token,
                refreshToken: params["refresh_token"],
                expiresIn: params["expires_in"].flatMap(Int.init)
            )
        }
        throw OAuthError.noCredentials
    }

    public func tokenRequest(code: String, pkce: PKCEChallenge) -> URLRequest? {
        guard let tokenURL else { return nil }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let form: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": pkce.verifier,
            "redirect_uri": redirectURI
        ]
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }
}

/// Decodes a standard OAuth 2.0 token-endpoint response.
public enum OAuthTokenResponse {
    public static func parse(_ data: Data, now: Date = .now) throws -> OAuthTokens {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            throw OAuthError.tokenExchangeFailed
        }
        let refresh = json["refresh_token"] as? String
        let expiresIn = (json["expires_in"] as? Int) ?? (json["expires_in"] as? Double).map { Int($0) }
        return OAuthTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
        )
    }
}

/// Ready-made OAuth settings for the supported trackers.
public enum TrackerOAuth {
    public static func myAnimeList(clientID: String, redirectURI: String) -> OAuthConfiguration {
        OAuthConfiguration(
            authorizeURL: URL(string: "https://myanimelist.net/v1/oauth2/authorize")!,
            tokenURL: URL(string: "https://myanimelist.net/v1/oauth2/token")!,
            clientID: clientID,
            redirectURI: redirectURI,
            scopes: [],
            flow: .authorizationCode
        )
    }

    public static func aniList(clientID: String, redirectURI: String) -> OAuthConfiguration {
        OAuthConfiguration(
            authorizeURL: URL(string: "https://anilist.co/api/v2/oauth/authorize")!,
            clientID: clientID,
            redirectURI: redirectURI,
            scopes: [],
            flow: .implicit
        )
    }
}
