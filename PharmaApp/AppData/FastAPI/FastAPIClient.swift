import Foundation
import Supabase

// MARK: - FastAPIClient

/// HTTP networking client that communicates with the PharmaApp FastAPI backend.
/// Automatically attaches the Supabase JWT access token and handles 401 retry (token refresh).
actor FastAPIClient {

    // MARK: - Types

    enum ClientError: LocalizedError {
        case noSession
        case baseURLMissing
        case httpError(statusCode: Int, body: Data?)
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .noSession:
                return "Nessuna sessione attiva. Esegui il login."
            case .baseURLMissing:
                return "URL del backend non configurato (FASTAPI_BASE_URL)."
            case .httpError(let code, _):
                return "Errore server: HTTP \(code)"
            case .decodingError(let err):
                return "Errore decodifica: \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Properties

    private let baseURL: URL
    private let supabaseClient: SupabaseClient
    private let session: URLSession
    private let decoder: JSONDecoder

    // MARK: - Init

    init(baseURL: URL, supabaseClient: SupabaseClient) {
        self.baseURL = baseURL
        self.supabaseClient = supabaseClient

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Try ISO8601 with fractional seconds first, then without
            if let date = ISO8601DateFormatter.fractional.date(from: string) {
                return date
            }
            if let date = ISO8601DateFormatter.standard.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(string)"
            )
        }
        self.decoder = decoder
    }

    // MARK: - Public API

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let request = try await buildRequest(method: "GET", path: path, query: query)
        return try await execute(request)
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let request = try await buildRequest(method: "POST", path: path, body: body)
        return try await execute(request)
    }

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let request = try await buildRequest(method: "PUT", path: path, body: body)
        return try await execute(request)
    }

    /// POST with pre-encoded JSON body data (used by SyncCoordinator for queued mutations).
    func postRaw<T: Decodable>(_ path: String, bodyData: Data) async throws -> T {
        let request = try await buildRawRequest(method: "POST", path: path, bodyData: bodyData)
        return try await execute(request)
    }

    /// PUT with pre-encoded JSON body data (used by SyncCoordinator for queued mutations).
    func putRaw<T: Decodable>(_ path: String, bodyData: Data) async throws -> T {
        let request = try await buildRawRequest(method: "PUT", path: path, bodyData: bodyData)
        return try await execute(request)
    }

    func delete(_ path: String) async throws {
        let request = try await buildRequest(method: "DELETE", path: path)
        let (_, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ClientError.httpError(statusCode: code, body: nil)
        }
    }

    // MARK: - Request Building

    private func buildRequest(
        method: String,
        path: String,
        query: [String: String] = [:],
        body: (some Encodable)? = nil as String?
    ) async throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let token = try await getAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    // Overload with raw Data body (pre-encoded JSON)
    private func buildRawRequest(
        method: String,
        path: String,
        bodyData: Data
    ) async throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let token = try await getAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        request.httpBody = bodyData
        return request
    }

    // Overload for requests without body
    private func buildRequest(
        method: String,
        path: String,
        query: [String: String] = [:]
    ) async throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let token = try await getAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return request
    }

    // MARK: - Execution with 401 Retry

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.httpError(statusCode: 0, body: data)
        }

        // On 401: refresh token and retry once
        if httpResponse.statusCode == 401 {
            try await refreshSession()
            var retryRequest = request
            let newToken = try await getAccessToken()
            retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await performRequest(retryRequest)
            guard let retryHTTP = retryResponse as? HTTPURLResponse,
                  (200...299).contains(retryHTTP.statusCode) else {
                let code = (retryResponse as? HTTPURLResponse)?.statusCode ?? 0
                throw ClientError.httpError(statusCode: code, body: retryData)
            }
            return try decoder.decode(T.self, from: retryData)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClientError.httpError(statusCode: httpResponse.statusCode, body: data)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ClientError.decodingError(error)
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    // MARK: - Token Management

    private func getAccessToken() async throws -> String {
        guard let session = try? await supabaseClient.auth.session else {
            throw ClientError.noSession
        }
        return session.accessToken
    }

    private func refreshSession() async throws {
        _ = try await supabaseClient.auth.refreshSession()
    }
}

// MARK: - ISO8601 Helpers

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
