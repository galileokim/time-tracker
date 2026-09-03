import Foundation

public struct AuthTokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresInSeconds: Int
}

public struct APIUser: Codable, Equatable, Sendable {
    public let id: UUID
    public let username: String
    public let displayName: String
    public let email: String
    public let avatarUrl: URL?
}

public struct APIErrorResponse: Decodable, Sendable {
    public struct Detail: Decodable, Sendable {
        public let code: String
        public let message: String?
    }
    public let error: Detail
}

public struct LogReceiptResponse: Decodable, Sendable {
    public let id: UUID
    public let idempotencyKey: UUID
    public let created: Bool
}

public enum APIClientError: Error, Equatable {
    case invalidResponse
    case server(statusCode: Int, code: String)
    case decoding
}

public struct TrackerAPIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func register(username: String, displayName: String, email: String, password: String) async throws -> APIUser {
        let request = try makeRequest(
            path: "/api/v1/auth/register",
            method: "POST",
            payload: RegisterPayload(username: username, displayName: displayName, email: email, password: password)
        )
        let response: UserEnvelope = try await send(request, as: UserEnvelope.self, expectedStatus: 201)
        return response.user
    }

    public func login(username: String, password: String) async throws -> AuthTokenResponse {
        let request = try makeRequest(
            path: "/api/v1/auth/login",
            method: "POST",
            payload: LoginPayload(username: username, password: password)
        )
        return try await send(request, as: AuthTokenResponse.self, expectedStatus: 200)
    }

    public func profile(accessToken: String) async throws -> APIUser {
        var request = try makeRequest(path: "/api/v1/me", method: "GET", payload: Optional<EmptyPayload>.none)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: UserEnvelope = try await send(request, as: UserEnvelope.self, expectedStatus: 200)
        return response.user
    }

    public func createLog(_ log: LocalActivityLog, accessToken: String) async throws -> LogReceiptResponse {
        let payload = CreateLogPayload(
            idempotencyKey: log.idempotencyKey,
            title: log.title,
            notes: log.notes,
            startedAt: log.startedAt,
            endedAt: log.endedAt,
            categoryIds: log.categoryIDs,
            visibility: log.visibility.rawValue
        )
        var request = try makeRequest(path: "/api/v1/logs", method: "POST", payload: payload)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request, as: LogReceiptResponse.self, expectedStatus: nil)
    }

    public func encodedLoginRequest(username: String, password: String) throws -> URLRequest {
        try makeRequest(
            path: "/api/v1/auth/login",
            method: "POST",
            payload: LoginPayload(username: username, password: password)
        )
    }

    public func encodedLogRequest(_ log: LocalActivityLog, accessToken: String) throws -> URLRequest {
        var request = try makeRequest(
            path: "/api/v1/logs",
            method: "POST",
            payload: CreateLogPayload(
                idempotencyKey: log.idempotencyKey,
                title: log.title,
                notes: log.notes,
                startedAt: log.startedAt,
                endedAt: log.endedAt,
                categoryIds: log.categoryIDs,
                visibility: log.visibility.rawValue
            )
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    func makeRequest<Payload: Encodable>(path: String, method: String, payload: Payload?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let payload {
            let body = try encoder.encode(payload)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
            request.httpBody = body
        }
        return request
    }

    func send<Response: Decodable>(
        _ request: URLRequest,
        as responseType: Response.Type,
        expectedStatus: Int?
    ) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        let acceptedStatus = expectedStatus.map { httpResponse.statusCode == $0 } ?? (200..<300).contains(httpResponse.statusCode)
        guard acceptedStatus else {
            let body = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIClientError.server(statusCode: httpResponse.statusCode, code: body?.error.code ?? "UNKNOWN_ERROR")
        }
        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            throw APIClientError.decoding
        }
    }
}

private struct RegisterPayload: Encodable {
    let username: String
    let displayName: String
    let email: String
    let password: String
}

private struct LoginPayload: Encodable {
    let username: String
    let password: String
}

struct CreateLogPayload: Encodable {
    let idempotencyKey: UUID
    let title: String
    let notes: String?
    let startedAt: Date
    let endedAt: Date
    let categoryIds: [UUID]
    let visibility: String
}

private struct UserEnvelope: Decodable {
    let user: APIUser
}

private struct EmptyPayload: Encodable {}
