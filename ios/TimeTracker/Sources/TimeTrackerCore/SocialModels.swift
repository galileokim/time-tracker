import Foundation

public struct SocialUser: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let username: String
    public let displayName: String
    public var isFollowing: Bool

    public init(id: UUID, username: String, displayName: String, isFollowing: Bool) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.isFollowing = isFollowing
    }
}

public struct FollowingUser: Decodable, Identifiable, Sendable {
    public let id: UUID
    public let username: String
    public let displayName: String
    public let avatarUrl: URL?
    public let followedAt: Date
}

public enum SocialClientError: Error, Equatable {
    case invalidUsername
    case followConflict
}

struct UserSearchEnvelope: Decodable {
    let users: [SocialUser]
}

struct FollowingEnvelope: Decodable {
    let following: [FollowingUser]
}

struct FollowPayload: Encodable {
    let userId: UUID
}
