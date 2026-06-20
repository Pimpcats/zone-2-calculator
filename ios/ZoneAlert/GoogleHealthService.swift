import Foundation
import SwiftUI
import UIKit

/// Connects to the **Google Health API** (which replaces the legacy Fitbit Web API)
/// using Google OAuth 2.0 — Web Server client flow: Client ID + Secret, redirect to
/// https://www.google.com, and a pasted authorization code. Scopes/data type are
/// editable in-app because Google's identifiers are new and account-specific.
final class GoogleHealthService: ObservableObject {
    @Published var clientID: String = UserDefaults.standard.string(forKey: "gh_clientID") ?? "" {
        didSet { UserDefaults.standard.set(clientID, forKey: "gh_clientID") }
    }
    @Published var clientSecret: String = UserDefaults.standard.string(forKey: "gh_clientSecret") ?? "" {
        didSet { UserDefaults.standard.set(clientSecret, forKey: "gh_clientSecret") }
    }
    @Published var scopes: String = UserDefaults.standard.string(forKey: "gh_scopes")
        ?? "https://www.googleapis.com/auth/health.activity.read https://www.googleapis.com/auth/health.heart_rate.read https://www.googleapis.com/auth/health.sleep.read" {
        didSet { UserDefaults.standard.set(scopes, forKey: "gh_scopes") }
    }
    @Published var dataType: String = UserDefaults.standard.string(forKey: "gh_dataType") ?? "heart_rate" {
        didSet { UserDefaults.standard.set(dataType, forKey: "gh_dataType") }
    }
    @Published var connected = false
    @Published var loading = false
    @Published var status = ""
    @Published var rawOutput = ""

    private let redirectURI = "https://www.google.com"
    private var accessToken: String?
    private var refreshToken: String?

    init() {
        accessToken = UserDefaults.standard.string(forKey: "gh_access")
        refreshToken = UserDefaults.standard.string(forKey: "gh_refresh")
        connected = accessToken != nil
    }

    // MARK: - OAuth (Web Server flow, paste-the-code)

    var authURL: URL? {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        return c.url
    }

    func openSignIn() {
        guard !clientID.isEmpty, let url = authURL else {
            status = "Enter your Client ID (and scopes) first."
            return
        }
        UIApplication.shared.open(url)
        status = "Authorize in the browser, then copy the whole redirected URL (or just the code=…) and paste it below."
    }

    func submit(_ pasted: String) {
        var code = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.contains("code="),
           let comps = URLComponents(string: code),
           let c = comps.queryItems?.first(where: { $0.name == "code" })?.value {
            code = c
        }
        guard !code.isEmpty else { status = "Paste the code or redirected URL first."; return }
        Task { await exchange(code: code) }
    }

    @MainActor
    private func exchange(code: String) async {
        loading = true; status = "Exchanging code for token…"
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form([
            "client_id": clientID, "client_secret": clientSecret,
            "code": code, "grant_type": "authorization_code", "redirect_uri": redirectURI,
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            status = "Token request failed (network)."; loading = false; return
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let access = json?["access_token"] as? String {
            accessToken = access
            refreshToken = json?["refresh_token"] as? String ?? refreshToken
            UserDefaults.standard.set(access, forKey: "gh_access")
            UserDefaults.standard.set(refreshToken, forKey: "gh_refresh")
            connected = true
            status = "Connected to Google Health ✓"
        } else {
            status = "Token error — see details below."
            rawOutput = String(data: data, encoding: .utf8) ?? ""
        }
        loading = false
    }

    func disconnect() {
        accessToken = nil; refreshToken = nil
        UserDefaults.standard.removeObject(forKey: "gh_access")
        UserDefaults.standard.removeObject(forKey: "gh_refresh")
        connected = false; rawOutput = ""; status = "Disconnected."
    }

    // MARK: - API (raw test call; we'll parse once we see a real response)

    func testFetch() { Task { await testFetchAsync(retry: true) } }

    @MainActor
    private func testFetchAsync(retry: Bool) async {
        guard let token = accessToken else { status = "Not connected."; return }
        loading = true; status = "Calling Google Health API…"
        let urlStr = "https://health.googleapis.com/v4/users/me/dataTypes/\(dataType)/dataPoints"
        guard let url = URL(string: urlStr) else { loading = false; return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            status = "Request failed (network)."; loading = false; return
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401, retry, await refresh() { await testFetchAsync(retry: false); return }
        let body = String(data: data, encoding: .utf8) ?? ""
        rawOutput = "GET \(urlStr)\nHTTP \(code)\n\n\(body)"
        status = "Done — HTTP \(code)"
        loading = false
    }

    private func refresh() async -> Bool {
        guard let rt = refreshToken else { return false }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form([
            "client_id": clientID, "client_secret": clientSecret,
            "refresh_token": rt, "grant_type": "refresh_token",
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { return false }
        accessToken = access
        UserDefaults.standard.set(access, forKey: "gh_access")
        return true
    }

    private static func form(_ dict: [String: String]) -> Data {
        dict.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .ghQuery) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

private extension CharacterSet {
    static let ghQuery: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return cs
    }()
}
