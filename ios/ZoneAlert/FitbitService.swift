import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit

/// One day of pulled Fitbit data.
struct FitbitDaily: Codable {
    var date = ""
    var name = ""
    var steps = 0
    var caloriesOut = 0
    var distanceMiles = 0.0
    var activeMinutes = 0
    var restingHR = 0
    var sleepMinutes = 0
}

/// Connects to the Fitbit Web API (OAuth 2.0 + PKCE) and pulls daily data.
/// Paste your Client ID (from dev.fitbit.com) into the Fitbit tab — no rebuild needed.
final class FitbitService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var clientID: String = UserDefaults.standard.string(forKey: "fitbitClientID") ?? "" {
        didSet { UserDefaults.standard.set(clientID, forKey: "fitbitClientID") }
    }
    @Published var connected = false
    @Published var loading = false
    @Published var status = ""
    @Published var daily = FitbitDaily()

    private let redirectScheme = "zonealert"
    private let redirectURI = "zonealert://fitbit"
    private var accessToken: String?
    private var refreshToken: String?
    private var verifier = ""
    private var authSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        accessToken = UserDefaults.standard.string(forKey: "fitbitAccess")
        refreshToken = UserDefaults.standard.string(forKey: "fitbitRefresh")
        connected = accessToken != nil
    }

    // MARK: - OAuth

    func connect() {
        guard !clientID.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = "Enter your Fitbit Client ID first."
            return
        }
        verifier = Self.randomString(64)
        let challenge = Self.codeChallenge(verifier)
        var comps = URLComponents(string: "https://www.fitbit.com/oauth2/authorize")!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "scope", value: "activity heartrate sleep profile weight"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "redirect_uri", value: redirectURI),
        ]
        guard let url = comps.url else { return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectScheme) { [weak self] callback, error in
            guard let self = self else { return }
            guard let callback = callback,
                  let code = URLComponents(string: callback.absoluteString)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else {
                DispatchQueue.main.async { self.status = "Login cancelled or failed." }
                return
            }
            self.exchange(code: code)
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        status = "Opening Fitbit login…"
        session.start()
    }

    func disconnect() {
        accessToken = nil; refreshToken = nil
        UserDefaults.standard.removeObject(forKey: "fitbitAccess")
        UserDefaults.standard.removeObject(forKey: "fitbitRefresh")
        connected = false
        daily = FitbitDaily()
        status = "Disconnected."
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    private func exchange(code: String) {
        var req = URLRequest(url: URL(string: "https://api.fitbit.com/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form([
            "client_id": clientID, "grant_type": "authorization_code",
            "code": code, "code_verifier": verifier, "redirect_uri": redirectURI,
        ])
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async {
                if let access = json["access_token"] as? String {
                    self.accessToken = access
                    self.refreshToken = json["refresh_token"] as? String
                    UserDefaults.standard.set(access, forKey: "fitbitAccess")
                    UserDefaults.standard.set(self.refreshToken, forKey: "fitbitRefresh")
                    self.connected = true
                    self.status = "Connected to Fitbit."
                    self.sync()
                } else {
                    self.status = "Token error — check your Client ID / redirect URL."
                }
            }
        }.resume()
    }

    // MARK: - Data pull

    func sync() { Task { await syncAsync() } }

    @MainActor
    private func syncAsync() async {
        guard accessToken != nil else { return }
        loading = true; status = "Syncing Fitbit…"
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        var d = FitbitDaily(); d.date = today

        if let p = await get("https://api.fitbit.com/1/user/-/profile.json"),
           let user = p["user"] as? [String: Any] {
            d.name = user["fullName"] as? String ?? ""
        }
        if let a = await get("https://api.fitbit.com/1/user/-/activities/date/\(today).json"),
           let s = a["summary"] as? [String: Any] {
            d.steps = s["steps"] as? Int ?? 0
            d.caloriesOut = s["caloriesOut"] as? Int ?? 0
            d.activeMinutes = (s["fairlyActiveMinutes"] as? Int ?? 0) + (s["veryActiveMinutes"] as? Int ?? 0)
            if let dists = s["distances"] as? [[String: Any]],
               let total = dists.first(where: { ($0["activity"] as? String) == "total" })?["distance"] as? Double {
                d.distanceMiles = total
            }
        }
        if let h = await get("https://api.fitbit.com/1/user/-/activities/heart/date/\(today)/1d.json"),
           let arr = h["activities-heart"] as? [[String: Any]],
           let val = arr.first?["value"] as? [String: Any] {
            d.restingHR = val["restingHeartRate"] as? Int ?? 0
        }
        if let sl = await get("https://api.fitbit.com/1.2/user/-/sleep/date/\(today).json"),
           let sum = sl["summary"] as? [String: Any] {
            d.sleepMinutes = sum["totalMinutesAsleep"] as? Int ?? 0
        }
        daily = d
        status = "Synced \(today)"
        loading = false
    }

    private func get(_ urlStr: String, retry: Bool = true) async -> [String: Any]? {
        guard let token = accessToken, let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        if (resp as? HTTPURLResponse)?.statusCode == 401, retry, await refresh() {
            return await get(urlStr, retry: false)
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func refresh() async -> Bool {
        guard let rt = refreshToken else { return false }
        var req = URLRequest(url: URL(string: "https://api.fitbit.com/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form(["grant_type": "refresh_token", "refresh_token": rt, "client_id": clientID])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { return false }
        accessToken = access
        refreshToken = json["refresh_token"] as? String ?? rt
        UserDefaults.standard.set(access, forKey: "fitbitAccess")
        UserDefaults.standard.set(refreshToken, forKey: "fitbitRefresh")
        return true
    }

    // MARK: - Helpers

    private static func form(_ dict: [String: String]) -> Data {
        dict.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8) ?? Data()
    }
    private static func randomString(_ n: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<n).map { _ in chars.randomElement()! })
    }
    private static func codeChallenge(_ verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return cs
    }()
}
