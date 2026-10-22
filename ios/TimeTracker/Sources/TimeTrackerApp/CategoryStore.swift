import Foundation

/// The signed-in user's categories, shared by the Timer and Profile tabs so both stay in sync.
@MainActor
@Observable
final class CategoryStore {
    private let api: TrackerAPIClient
    private let token: String
    private(set) var categories: [APICategory] = []
    private(set) var isLoading = false
    private(set) var isCreating = false

    init(api: TrackerAPIClient, token: String) {
        self.api = api
        self.token = token
    }

    func category(withID id: UUID?) -> APICategory? {
        categories.first { $0.id == id }
    }

    func reload() async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        categories = try await api.categories(accessToken: token)
    }

    func create(named name: String) async throws -> APICategory {
        isCreating = true
        defer { isCreating = false }
        let category = try await api.createCategory(name: name, accessToken: token)
        categories.append(category)
        return category
    }
}
