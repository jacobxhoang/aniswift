import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

struct Page<Value> {
    let items: [Value]
    let more: Bool
}

private enum SessionKeychain {
    static let key: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.aniledger.ios",
        kSecAttrAccount as String: "mal-session"
    ]

    static func read() -> String? {
        var query = key
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ token: String?) throws {
        guard let token else {
            let status = SecItemDelete(key as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure() }
            return
        }
        let value = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(key as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var query = key.merging(value) { _, new in new }
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw failure() }
        } else if status != errSecSuccess { throw failure() }
    }

    static func failure() -> APIError {
        APIError(status: 0, message: "Could not save the MyAnimeList session.")
    }
}

@MainActor
final class API {
    static let backend = URL(string: "https://ani-ledger.onrender.com")!
    private let tenrai = URL(string: "https://api.tenrai.org/v1")!
    private let jikan = URL(string: "https://jikan.lucashdo.com/v1")!
    private var token = SessionKeychain.read()
    private var privateQueue: Task<Void, Never>?
    private var cached: [URL: (Date, Fields)] = [:]
    private var nextTitleLookup = ContinuousClock().now

    static func url(_ base: URL, _ path: String, _ query: [URLQueryItem] = []) -> URL {
        let url = base.appending(path: path)
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        return parts.url!
    }

    private func request(_ request: URLRequest) async throws -> (Fields, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "The server did not respond.")
        }
        let fields = try? JSONDecoder().decode(Fields.self, from: data)
        guard (200..<300).contains(http.statusCode), let fields else {
            throw APIError(status: http.statusCode, message: fields?.string("error") ?? "The request could not be completed.")
        }
        return (fields, http)
    }

    func catalog(_ path: String, _ query: [URLQueryItem] = [], refresh: Bool = false) async throws -> Fields {
        let publicUserData = path.hasPrefix("users/")
        let cacheKey = Self.url(publicUserData ? jikan : tenrai, path, query)
        if !refresh, let (date, result) = cached[cacheKey], Date().timeIntervalSince(date) < 60 { return result }
        for base in publicUserData ? [jikan] : [tenrai, jikan] {
            do {
                let url = Self.url(base, path, query)
                let response = try await request(URLRequest(url: url, timeoutInterval: base == tenrai ? 5 : 10)).0
                cached[cacheKey] = (Date(), response)
                return response
            } catch {
                try Task.checkCancellation()
                if base == jikan { throw error }
            }
        }
        throw APIError(status: 0, message: "Catalog unavailable.")
    }

    func resolveTitle(_ title: Title) async -> Title? {
        let path = "\(title.kind.rawValue)/\(title.malID)"
        let key = Self.url(tenrai, path)
        while !Task.isCancelled {
            if let (date, response) = cached[key], Date().timeIntervalSince(date) < 60,
               let fields: Fields = response.read("data") {
                return Title(fields, kind: title.kind)
            }
            let now = ContinuousClock().now
            if now >= nextTitleLookup {
                nextTitleLookup = now.advanced(by: .milliseconds(270))
                guard let response = try? await catalog(path), let fields: Fields = response.read("data") else { return nil }
                return Title(fields, kind: title.kind)
            }
            do { try await Task.sleep(until: nextTitleLookup, clock: .continuous) }
            catch { return nil }
        }
        return nil
    }

    // Serialize authenticated requests so a rotated MAL refresh token is never used twice.
    private func privateRequest(_ path: String, _ query: [URLQueryItem] = [],
                                method: String = "GET", body: Data? = nil) async throws -> Fields {
        let previous = privateQueue
        let job = Task { @MainActor in
            await previous?.value
            return try await self.sendPrivate(path, query, method: method, body: body)
        }
        privateQueue = Task { _ = try? await job.value }
        return try await job.value
    }

    private func sendPrivate(_ path: String, _ query: [URLQueryItem],
                             method: String, body: Data?) async throws -> Fields {
        var req = URLRequest(url: Self.url(Self.backend, path, query), timeoutInterval: 25)
        req.httpMethod = method
        req.httpShouldHandleCookies = false
        let current = token
        if let current { req.setValue("Bearer \(current)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (fields, response) = try await request(req)
            if let renewed = response.value(forHTTPHeaderField: "X-AniLedger-Session"), token == current {
                try SessionKeychain.write(renewed)
                token = renewed
            }
            return fields
        } catch let error as APIError where error.status == 401 && current != nil && current == token {
            try signOut()
            throw error
        }
    }

    var hasSession: Bool { token != nil }

    func session() async throws -> Account? {
        guard token != nil else { return nil }
        let response = try await privateRequest("api/session")
        let account: Account? = response.read("user")
        if account == nil { try signOut() }
        return account
    }

    func signOut() throws {
        try SessionKeychain.write(nil)
        token = nil
    }

    func signIn() async throws -> Account {
        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw SessionKeychain.failure() }
        func base64url(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let verifier = base64url(Data(bytes))
        let challenge = base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let start = Self.url(Self.backend, "auth/mobile", [URLQueryItem(name: "challenge", value: challenge)])
        let callback = try await LoginBrowser().authenticate(start)
        let values = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard callback.scheme == "aniledger", callback.host == "auth",
              let handoff = values.first(where: { $0.name == "handoff" })?.value else {
            throw APIError(status: 0, message: "MyAnimeList sign-in did not complete.")
        }
        let body = try JSONEncoder().encode(["handoff": handoff, "verifier": verifier])
        let response = try await privateRequest("api/mobile/exchange", method: "POST", body: body)
        guard let account: Account = response.read("user"), let next = response.string("token") else {
            throw APIError(status: 0, message: "MyAnimeList returned an invalid session.")
        }
        try SessionKeychain.write(next)
        token = next
        return account
    }

    func list(_ kind: Kind, page: Int) async throws -> Page<ListEntry> {
        let response = try await privateRequest("api/lists/\(kind.rawValue)", [URLQueryItem(name: "page", value: String(page))])
        let entries: [Fields] = response.read("entries") ?? []
        return Page(items: entries.compactMap { ListEntry($0, kind: kind) }, more: response.read("hasNext") ?? false)
    }

    func suggestions() async throws -> [Title] {
        let response = try await privateRequest("api/suggestions/anime")
        let entries: [Fields] = response.read("entries") ?? []
        return entries.compactMap { Title($0, kind: .anime) }
    }

    func save(_ title: Title, change: ListChange?) async throws {
        let body = try change.map { try JSONEncoder().encode($0) }
        _ = try await privateRequest("api/lists/\(title.kind.rawValue)/\(title.malID)", method: change == nil ? "DELETE" : "PUT", body: body)
    }
}

func catalogPage(_ result: Fields, kind: Kind) -> Page<Title> {
    let body: Fields? = result.read("data")
    let entries: [Fields] = result.read("data") ?? body?.read("entries", "items", "anime") ?? []
    let pagination: Fields? = result.read("pagination")
    let meta: Fields? = result.read("meta")
    let metaPagination: Fields? = meta?.read("pagination")
    return Page(items: entries.compactMap { Title($0, kind: kind) },
                more: pagination?.read("has_next_page") ?? metaPagination?.read("hasNextPage") ?? false)
}

func recommendations(_ result: Fields, kind: Kind) -> [Title] {
    let entries: [Fields] = result.read("data") ?? []
    return entries.flatMap { item in
        if let children: [Fields] = item.read("entry", "entries") { return children }
        if let child: Fields = item.read("entry") { return [child] }
        return [item]
    }.compactMap { Title($0, kind: kind) }
}

@MainActor
private final class LoginBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private let window: UIWindow? = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
        .compactMap { $0.windows.first(where: \.isKeyWindow) }.first

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window!
    }

    func authenticate(_ start: URL) async throws -> URL {
        guard window != nil else { throw APIError(status: 0, message: "Bring AniLedger to the foreground and try again.") }
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let browser = ASWebAuthenticationSession(url: start, callbackURLScheme: "aniledger") { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? APIError(status: 0, message: "Sign-in did not complete.")) }
            }
            browser.presentationContextProvider = self
            session = browser
            if !browser.start() {
                continuation.resume(throwing: APIError(status: 0, message: "Unable to start MyAnimeList sign-in."))
            }
        }
    }
}
