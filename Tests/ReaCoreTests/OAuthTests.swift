import XCTest
@testable import ReaCore

final class OAuthTests: XCTestCase {
    private func config(flow: OAuthConfiguration.Flow) -> OAuthConfiguration {
        OAuthConfiguration(
            authorizeURL: URL(string: "https://example.com/authorize")!,
            tokenURL: URL(string: "https://example.com/token")!,
            clientID: "client-1",
            redirectURI: "rea://oauth/example",
            scopes: ["read"],
            flow: flow
        )
    }

    func testAuthorizationURLIncludesPKCE() {
        let pkce = PKCEChallenge.random()
        let url = config(flow: .authorizationCode).authorizationURL(state: "abc", pkce: pkce)
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: comps.queryItems!.map { ($0.name, $0.value) })
        XCTAssertEqual(items["code_challenge"], pkce.challenge)
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["state"], "abc")
        XCTAssertEqual(items["response_type"], "code")
    }

    func testParseCodeCallback() throws {
        let url = URL(string: "rea://oauth/example?code=xyz&state=abc")!
        let callback = try config(flow: .authorizationCode).parseCallback(url, expectedState: "abc")
        XCTAssertEqual(callback, .code("xyz"))
    }

    func testParseFragmentToken() throws {
        let url = URL(string: "rea://oauth/example#access_token=t1&refresh_token=r1&expires_in=3600")!
        let callback = try config(flow: .implicit).parseCallback(url, expectedState: "")
        guard case .token(let access, let refresh, let expires) = callback else {
            return XCTFail("Expected token callback")
        }
        XCTAssertEqual(access, "t1")
        XCTAssertEqual(refresh, "r1")
        XCTAssertEqual(expires, 3600)
    }

    func testStateMismatchThrows() {
        let url = URL(string: "rea://oauth/example?code=xyz&state=other")!
        XCTAssertThrowsError(try config(flow: .authorizationCode).parseCallback(url, expectedState: "abc")) { error in
            XCTAssertEqual(error as? OAuthError, .stateMismatch)
        }
    }

    func testDeniedAuthorizationThrows() {
        let url = URL(string: "rea://oauth/example?error=access_denied&state=abc")!
        XCTAssertThrowsError(try config(flow: .authorizationCode).parseCallback(url, expectedState: "abc")) { error in
            XCTAssertEqual(error as? OAuthError, .authorizationDenied("access_denied"))
        }
    }

    func testTokenRequestCarriesVerifier() {
        let pkce = PKCEChallenge.random()
        let request = config(flow: .authorizationCode).tokenRequest(code: "c0de", pkce: pkce)
        let body = String(data: request?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("code_verifier=\(pkce.verifier)"))
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
    }

    func testTokenResponseParsing() throws {
        let payload = Data(#"{"access_token":"a","refresh_token":"r","expires_in":60}"#.utf8)
        let now = Date()
        let tokens = try OAuthTokenResponse.parse(payload, now: now)
        XCTAssertEqual(tokens.accessToken, "a")
        XCTAssertEqual(tokens.refreshToken, "r")
        XCTAssertFalse(tokens.isExpired)
        XCTAssertEqual(tokens.expiresAt?.timeIntervalSince(now), 60, accuracy: 0.5)
    }

    func testPKCEChallengeIsDeterministic() {
        let pair = PKCEChallenge(verifier: "fixed-verifier")
        XCTAssertEqual(pair.challenge, PKCEChallenge.s256("fixed-verifier"))
        XCTAssertEqual(pair.method, "S256")
        XCTAssertFalse(pair.challenge.contains("="))
    }
}
