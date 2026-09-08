import Foundation
import Testing
@testable import TimeTrackerCore

@Suite(.serialized)
struct APIClientTests {
    @Test func encodesLoginRequestPayload() throws {
        let client = TrackerAPIClient(baseURL: URL(string: "https://tracker.example.test")!)
        let request = try client.encodedLoginRequest(username: "demo-user", password: "correct horse battery staple")
        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(request.url?.path == "/api/v1/auth/login")
        #expect(request.httpMethod == "POST")
        #expect(payload["username"] == "demo-user")
        #expect(payload["password"] == "correct horse battery staple")
    }

    @Test func loginDecodesBearerTokenAndUsesEndpoint() async throws {
        let responseBody = Data(#"{"accessToken":"signed-token","tokenType":"Bearer","expiresInSeconds":900}"#.utf8)
        let session = stubbedSession { request in
            #expect(request.url?.absoluteString == "https://tracker.example.test/api/v1/auth/login")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            return response(body: responseBody, statusCode: 200)
        }

        let client = TrackerAPIClient(baseURL: URL(string: "https://tracker.example.test")!, session: session)
        let tokens = try await client.login(username: "demo-user", password: "correct horse battery staple")
        #expect(tokens.accessToken == "signed-token")
        #expect(tokens.tokenType == "Bearer")
        #expect(tokens.expiresInSeconds == 900)
    }

    @Test func profileAttachesBearerTokenAndDecodesUser() async throws {
        let responseBody = Data(#"{"user":{"id":"A93FCBEA-EEA7-4651-99D7-AF544F278DD1","username":"demo-user","displayName":"Demo User","email":"demo@example.test","avatarUrl":null}}"#.utf8)
        let session = stubbedSession { request in
            #expect(request.url?.path == "/api/v1/me")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
            return response(body: responseBody, statusCode: 200)
        }

        let client = TrackerAPIClient(baseURL: URL(string: "https://tracker.example.test")!, session: session)
        let user = try await client.profile(accessToken: "access-token")
        #expect(user.username == "demo-user")
        #expect(user.displayName == "Demo User")
        #expect(user.avatarUrl == nil)
    }

    @Test func categoriesDecodesAuthenticatedResponse() async throws {
        let categoryID = UUID()
        let responseBody = Data("""
        {"categories":[{"id":"\(categoryID)","name":"Writing","colorHex":"#345678","createdAt":"2026-02-08T12:00:00Z"}]}
        """.utf8)
        let session = stubbedSession { request in
            #expect(request.url?.path == "/api/v1/categories")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
            return response(body: responseBody, statusCode: 200)
        }
        let client = TrackerAPIClient(baseURL: URL(string: "https://tracker.example.test")!, session: session)

        let categories = try await client.categories(accessToken: "access-token")

        #expect(categories == [APICategory(id: categoryID, name: "Writing", colorHex: "#345678", createdAt: ISO8601DateFormatter().date(from: "2026-02-08T12:00:00Z"))])
    }

    @Test func updateProfileSendsDisplayNameAndDecodesUser() async throws {
        let profileID = UUID()
        let body = Data("""
        {"user":{"id":"\(profileID)","username":"demo-user","displayName":"New Name","email":"demo@example.test","avatarUrl":null,"createdAt":"2026-02-08T12:00:00Z"}}
        """.utf8)
        let session = stubbedSession { request in
            let requestBody = try #require(requestBodyData(request))
            let payload = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: String])
            #expect(payload["displayName"] == "New Name")
            #expect(request.url?.path == "/api/v1/me")
            #expect(request.httpMethod == "PATCH")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
            return response(body: body, statusCode: 200)
        }
        let client = TrackerAPIClient(baseURL: URL(string: "https://tracker.example.test")!, session: session)

        let profile = try await client.updateProfile(displayName: "New Name", accessToken: "access-token")

        #expect(profile.id == profileID)
        #expect(profile.displayName == "New Name")
    }

    @Test func createCategoryMapsDuplicateConflict() async throws {
        let body = Data(#"{"error":{"code":"CATEGORY_CONFLICT","message":"Category name already exists"}}"#.utf8)
        let session = stubbedSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
            return response(body: body, statusCode: 409)
        }
        let client = TrackerAPIClient(baseURL: URL(string: "https://tracker.example.test")!, session: session)

        await #expect(throws: ProfileClientError.duplicateCategory) {
            try await client.createCategory(name: "Writing", accessToken: "access-token")
        }
    }

    @Test func createCategoryReturnsCreatedCategory() async throws {
        let categoryID = UUID()
        let body = Data("""
        {"category":{"id":"\(categoryID)","name":"Writing","colorHex":"#4A6C45","createdAt":"2026-02-08T12:00:00Z"}}
        """.utf8)
        let session = stubbedSession { request in
            #expect(request.httpMethod == "POST")
            let requestBody = try #require(requestBodyData(request))
            let payload = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: String])
            #expect(payload["name"] == "Writing")
            return response(body: body, statusCode: 201)
        }
        let client = TrackerAPIClient(baseURL: URL(string: "https://tracker.example.test")!, session: session)

        let category = try await client.createCategory(name: "Writing", accessToken: "access-token")

        #expect(category.id == categoryID)
        #expect(category.colorHex == "#4A6C45")
    }

    @Test func failedLoginMapsStructuredServerError() async throws {
        let body = Data(#"{"error":{"code":"INVALID_CREDENTIALS","message":"Invalid username or password"}}"#.utf8)
        let client = TrackerAPIClient(
            baseURL: URL(string: "https://tracker.example.test")!,
            session: stubbedSession { _ in response(body: body, statusCode: 401) }
        )

        await #expect(throws: APIClientError.server(statusCode: 401, code: "INVALID_CREDENTIALS")) {
            try await client.login(username: "missing-user", password: "wrong-password")
        }
    }

    private func stubbedSession(
        responder: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)
    ) -> URLSession {
        let protocolType = makeStubProtocol(responder: responder)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolType]
        return URLSession(configuration: configuration)
    }

    private func response(body: Data, statusCode: Int) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://tracker.example.test")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (body, response)
    }
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let httpBody = request.httpBody { return httpBody }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: 4096)
        if count < 0 { return nil }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private func makeStubProtocol(
    responder: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)
) -> URLProtocol.Type {
    final class StubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var responder: (@Sendable (URLRequest) throws -> (Data, URLResponse))!

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            do {
                let (data, response) = try Self.responder(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    StubURLProtocol.responder = responder
    return StubURLProtocol.self
}
