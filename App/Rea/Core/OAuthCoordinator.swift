import Foundation
import ReaCore
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Per-tracker client credentials, read from Info.plist so nothing is baked
/// into source. Add your own app registrations to the Info.plist keys.
struct TrackerClientConfig {
    let trackerID: String
    let clientID: String
    let redirectURI: String

    static func load(_ trackerID: String) -> TrackerClientConfig? {
        let bundle = Bundle.main
        let key = "ReaTracker." + trackerID
        guard let dict = bundle.object(forInfoDictionaryKey: key) as? [String: String],
              let clientID = dict["ClientID"], !clientID.isEmpty else {
            return nil
        }
        let redirect = dict["RedirectURI"] ?? "rea://oauth/\(trackerID)"
        return TrackerClientConfig(trackerID: trackerID, clientID: clientID, redirectURI: redirect)
    }

    var oauth: OAuthConfiguration? {
        switch trackerID {
        case "myanimelist":
            return TrackerOAuth.myAnimeList(clientID: clientID, redirectURI: redirectURI)
        case "anilist":
            return TrackerOAuth.aniList(clientID: clientID, redirectURI: redirectURI)
        default:
            return nil
        }
    }
}

/// Runs the OAuth dance and persists tokens to the same UserDefaults keys the
/// trackers' `DefaultsTokenProvider` reads.
@MainActor
final class OAuthCoordinator: NSObject, ObservableObject {
    enum State: Equatable {
        case idle, running, success, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var activeTracker: String?

    private var session: ASWebAuthenticationSession?
    private var configuration: OAuthConfiguration?
    private var pkce: PKCEChallenge?
    private var stateToken: String = ""

    func start(_ trackerID: String, config: TrackerClientConfig) {
        guard let oauth = config.oauth else {
            state = .failed("No OAuth preset for \(trackerID)")
            return
        }
        configuration = oauth
        activeTracker = trackerID
        pkce = oauth.flow == .authorizationCode ? .random() : nil
        stateToken = UUID().uuidString
        state = .running

        let url = oauth.authorizationURL(state: stateToken, pkce: pkce)
        #if canImport(AuthenticationServices)
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: URL(string: config.redirectURI)?.scheme
        ) { [weak self] callback, error in
            Task { @MainActor in
                self?.handleCallback(callback, error: error)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        if !session.start() {
            state = .failed("Could not open the sign-in sheet")
        }
        #else
        state = .failed("AuthenticationServices unavailable on this platform")
        #endif
    }

    private func handleCallback(_ callback: URL?, error: Error?) {
        defer { session = nil }
        if let error {
            let nsError = error as NSError
            if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                state = .idle
            } else {
                state = .failed(error.localizedDescription)
            }
            return
        }
        guard let callback, let configuration else {
            state = .failed("No callback received")
            return
        }
        do {
            let parsed = try configuration.parseCallback(callback, expectedState: stateToken)
            switch parsed {
            case .token(let access, let refresh, let expiresIn):
                storeTokens(access: access, refresh: refresh, expiresIn: expiresIn)
                state = .success
            case .code(let code):
                Task { await exchangeCode(code, configuration: configuration) }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func exchangeCode(_ code: String, configuration: OAuthConfiguration) async {
        guard let pkce, let request = configuration.tokenRequest(code: code, pkce: pkce) else {
            state = .failed("Missing token endpoint")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                state = .failed("Token exchange rejected")
                return
            }
            let tokens = try OAuthTokenResponse.parse(data)
            let lifetime = tokens.expiresAt.map { Int($0.timeIntervalSinceNow) }
            storeTokens(access: tokens.accessToken, refresh: tokens.refreshToken, expiresIn: lifetime)
            state = .success
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func storeTokens(access: String, refresh: String?, expiresIn: Int?) {
        guard let tracker = activeTracker else { return }
        let defaults = UserDefaults.standard
        defaults.set(access, forKey: "rea.tracker.\(tracker).token")
        if let refresh { defaults.set(refresh, forKey: "rea.tracker.\(tracker).refresh") }
        if let expiresIn {
            defaults.set(Date().addingTimeInterval(TimeInterval(expiresIn)), forKey: "rea.tracker.\(tracker).expiry")
        }
    }

    func signOut(_ trackerID: String) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "rea.tracker.\(trackerID).token")
        defaults.removeObject(forKey: "rea.tracker.\(trackerID).refresh")
        defaults.removeObject(forKey: "rea.tracker.\(trackerID).expiry")
        state = .idle
    }
}

#if canImport(AuthenticationServices)
extension OAuthCoordinator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        if let window = scene?.windows.first(where: \.isKeyWindow) {
            return window
        }
        return ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
