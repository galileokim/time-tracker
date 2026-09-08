import Foundation

public struct FeedEntry: Codable, Equatable, Sendable, Identifiable {
    public struct Author: Codable, Equatable, Sendable {
        public let id: UUID
        public let username: String
        public let displayName: String
        public let avatarUrl: URL?
    }

    public struct Category: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public let colorHex: String
    }

    public let id: UUID
    public let title: String
    public let notes: String?
    public let startedAt: Date
    public let endedAt: Date
    public let durationSeconds: Int
    public let visibility: ActivityVisibility
    public let createdAt: Date
    public let author: Author
    public let categories: [Category]
}

public struct FeedPage: Decodable, Equatable, Sendable {
    public let items: [FeedEntry]
    public let nextCursor: String?
}

enum FeedClientError: Error, Equatable {
    case invalidCursor
}
