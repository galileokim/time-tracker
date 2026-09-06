import Foundation

public struct APIProfile: Codable, Equatable, Sendable {
    public let id: UUID
    public let username: String
    public let displayName: String
    public let email: String
    public let avatarUrl: URL?
    public let createdAt: Date?

    public init(id: UUID, username: String, displayName: String, email: String, avatarUrl: URL?, createdAt: Date? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
    }
}

public struct APICategory: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let createdAt: Date?

    public init(id: UUID, name: String, colorHex: String, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

struct ProfileEnvelope: Decodable {
    let user: APIProfile
}

struct CategoriesEnvelope: Decodable {
    let categories: [APICategory]
}

struct CategoryEnvelope: Decodable {
    let category: APICategory
}

struct UpdateProfilePayload: Encodable {
    let displayName: String
    let avatarUrl: URL?

    enum CodingKeys: String, CodingKey {
        case displayName
        case avatarUrl
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        if let avatarUrl {
            try container.encode(avatarUrl, forKey: .avatarUrl)
        }
    }
}

struct CreateCategoryPayload: Encodable {
    let name: String
    let colorHex: String?

    enum CodingKeys: String, CodingKey {
        case name
        case colorHex
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let colorHex {
            try container.encode(colorHex, forKey: .colorHex)
        }
    }
}

public struct CategoryConflictError: Error, Equatable {}

public enum ProfileClientError: Error, Equatable {
    case duplicateCategory
}
