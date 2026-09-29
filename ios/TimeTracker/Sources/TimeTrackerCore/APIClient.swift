import Foundation

public struct AuthTokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresInSeconds: Int
}

public struct APIUser: Codable, Equatable, Sendable {
    public let id: UUID
    public let username: String
    public var displayName: String
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func register(username: String, displayName: String, email: String, password: String) async throws -> APIUser {
        let request = try makeBodyfulRequest(
            path: "/api/v1/auth/register",
            method: "POST",
            payload: RegisterPayload(username: username, displayName: displayName, email: email, password: password)
        )
        let response: UserEnvelope = try await send(request, as: UserEnvelope.self, expectedStatus: 201)
        return response.user
    }

    public func login(username: String, password: String) async throws -> AuthTokenResponse {
        let request = try makeBodyfulRequest(
            path: "/api/v1/auth/login",
            method: "POST",
            payload: LoginPayload(username: username, password: password)
        )
        return try await send(request, as: AuthTokenResponse.self, expectedStatus: 200)
    }

    public func profile(accessToken: String) async throws -> APIUser {
        var request = try makeBodylessRequest(path: "/api/v1/me", method: "GET")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: UserEnvelope = try await send(request, as: UserEnvelope.self, expectedStatus: 200)
        return response.user
    }

    public func updateProfile(displayName: String, accessToken: String) async throws -> APIProfile {
        var request = try makeBodyfulRequest(
            path: "/api/v1/me",
            method: "PATCH",
            payload: UpdateProfilePayload(displayName: displayName, avatarUrl: nil)
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: ProfileEnvelope = try await send(request, as: ProfileEnvelope.self, expectedStatus: 200)
        return response.user
    }

    public func categories(accessToken: String) async throws -> [APICategory] {
        var request = try makeBodylessRequest(path: "/api/v1/categories", method: "GET")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: CategoriesEnvelope = try await send(request, as: CategoriesEnvelope.self, expectedStatus: 200)
        return response.categories
    }

    public func createCategory(name: String, colorHex: String? = nil, accessToken: String) async throws -> APICategory {
        var request = try makeBodyfulRequest(
            path: "/api/v1/categories",
            method: "POST",
            payload: CreateCategoryPayload(name: name, colorHex: colorHex)
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        do {
            let response: CategoryEnvelope = try await send(request, as: CategoryEnvelope.self, expectedStatus: 201)
            return response.category
        } catch APIClientError.server(_, let code) where code == "CATEGORY_CONFLICT" {
            throw ProfileClientError.duplicateCategory
        }
    }

    public func searchUsers(username: String, accessToken: String) async throws -> [SocialUser] {
        let query = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3, query.count <= 50 else { throw SocialClientError.invalidUsername }
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "username", value: query)]
        guard let encodedQuery = components.percentEncodedQuery else { throw APIClientError.invalidResponse }
        var request = try makeBodylessRequest(path: "/api/v1/users/search?\(encodedQuery)", method: "GET")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: UserSearchEnvelope = try await send(request, as: UserSearchEnvelope.self, expectedStatus: 200)
        return response.users
    }

    public func following(accessToken: String) async throws -> [FollowingUser] {
        var request = try makeBodylessRequest(path: "/api/v1/follows", method: "GET")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: FollowingEnvelope = try await send(request, as: FollowingEnvelope.self, expectedStatus: 200)
        return response.following
    }

    public func follow(userID: UUID, accessToken: String) async throws {
        var request = try makeBodyfulRequest(path: "/api/v1/follows", method: "POST", payload: FollowPayload(userId: userID))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        do {
            try await sendNoContent(request, expectedStatus: 204)
        } catch APIClientError.server(400, let code) where code == "SELF_FOLLOW_NOT_ALLOWED" {
            throw SocialClientError.followConflict
        }
    }

    public func unfollow(userID: UUID, accessToken: String) async throws {
        var request = try makeBodylessRequest(path: "/api/v1/follows/\(userID.uuidString)", method: "DELETE")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        try await sendNoContent(request, expectedStatus: 204)
    }

    public func feedPage(accessToken: String, cursor: String? = nil, limit: Int = 20) async throws -> FeedPage {
        guard (1...100).contains(limit) else { throw APIClientError.invalidResponse }
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor, !cursor.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor))
        }
        guard let query = components.percentEncodedQuery else { throw APIClientError.invalidResponse }
        var request = try makeBodylessRequest(path: "/api/v1/feed?\(query)", method: "GET")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request, as: FeedPage.self, expectedStatus: 200)
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
        var request = try makeBodyfulRequest(path: "/api/v1/logs", method: "POST", payload: payload)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request, as: LogReceiptResponse.self, expectedStatus: nil)
    }

    public func encodedLoginRequest(username: String, password: String) throws -> URLRequest {
        try makeBodyfulRequest(
            path: "/api/v1/auth/login",
            method: "POST",
            payload: LoginPayload(username: username, password: password)
        )
    }

    public func encodedLogRequest(_ log: LocalActivityLog, accessToken: String) throws -> URLRequest {
        var request = try makeBodyfulRequest(
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

    func makeBodyfulRequest<Payload: Encodable>(path: String, method: String, payload: Payload) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = try encoder.encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = body
        return request
    }

    func makeBodylessRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func sendNoContent(_ request: URLRequest, expectedStatus: Int) async throws {
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard httpResponse.statusCode == expectedStatus else {
            throw APIClientError.server(statusCode: httpResponse.statusCode, code: "UNKNOWN_ERROR")
        }
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
private struct EmptyResponse: Decodable {}
