import SwiftUI

@MainActor
@Observable
final class FollowManagementModel {
    private let api: TrackerAPIClient
    private let token: String
    private(set) var results: [SocialUser] = []
    private(set) var following: [FollowingUser] = []
    private(set) var isSearching = false
    private(set) var isLoadingFollowing = false
    private(set) var isUpdatingUserID: UUID?
    private(set) var hasSearched = false
    var username = ""
    var errorMessage: String?

    init(api: TrackerAPIClient, token: String) {
        self.api = api
        self.token = token
    }

    func loadFollowing() async {
        guard !isLoadingFollowing else { return }
        isLoadingFollowing = true
        defer { isLoadingFollowing = false }
        do {
            following = try await api.following(accessToken: token)
        } catch {
            errorMessage = "Following list could not be loaded. Try again."
        }
    }

    func search() async {
        let query = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else {
            errorMessage = "Enter at least three username characters."
            return
        }
        isSearching = true
        hasSearched = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            results = try await api.searchUsers(username: query, accessToken: token)
        } catch {
            errorMessage = "Users could not be searched. Check your connection and try again."
        }
    }

    func toggleFollow(_ user: SocialUser) async {
        isUpdatingUserID = user.id
        errorMessage = nil
        defer { isUpdatingUserID = nil }
        do {
            if user.isFollowing {
                try await api.unfollow(userID: user.id, accessToken: token)
            } else {
                try await api.follow(userID: user.id, accessToken: token)
            }
            if let index = results.firstIndex(where: { $0.id == user.id }) {
                results[index] = SocialUser(
                    id: user.id,
                    username: user.username,
                    displayName: user.displayName,
                    isFollowing: !user.isFollowing
                )
            }
            await loadFollowing()
        } catch {
            errorMessage = user.isFollowing ? "Could not unfollow this account. Try again." : "Could not follow this account. Try again."
        }
    }
}

struct FollowManagementView: View {
    @State private var model: FollowManagementModel?
    let api: TrackerAPIClient
    let token: String

    var body: some View {
        Group {
            if let model {
                content(model)
                    .task { await model.loadFollowing() }
            } else {
                ProgressView("Opening people")
                    .task { model = FollowManagementModel(api: api, token: token) }
            }
        }
        .navigationTitle("People")
    }

    private func content(_ model: FollowManagementModel) -> some View {
        List {
            Section("Find people") {
                HStack(spacing: 10) {
                    TextField("Username", text: Binding(
                        get: { model.username },
                        set: { model.username = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await model.search() } }

                    Button(model.isSearching ? "Searching" : "Search") {
                        Task { await model.search() }
                    }
                    .frame(minWidth: 64, minHeight: 44)
                    .disabled(model.isSearching)
                }

                if model.isSearching {
                    ProgressView("Searching usernames")
                } else if model.hasSearched && model.results.isEmpty && model.errorMessage == nil {
                    Text("No accounts matched. Try another username.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.results) { user in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.displayName)
                                    .font(.headline)
                                Text("@\(user.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button(model.isUpdatingUserID == user.id ? "Saving" : (user.isFollowing ? "Following" : "Follow")) {
                                Task { await model.toggleFollow(user) }
                            }
                            .frame(minWidth: 82, minHeight: 44)
                            .disabled(model.isUpdatingUserID != nil)
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }

            Section("Following") {
                if model.isLoadingFollowing && model.following.isEmpty {
                    ProgressView("Loading followed accounts")
                } else if model.following.isEmpty {
                    Text("You are not following anyone yet. Search by username above to find people.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.following) { user in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.displayName)
                                    .font(.headline)
                                Text("@\(user.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unfollow") {
                                Task {
                                    await model.toggleFollow(SocialUser(
                                        id: user.id,
                                        username: user.username,
                                        displayName: user.displayName,
                                        isFollowing: true
                                    ))
                                }
                            }
                            .frame(minWidth: 82, minHeight: 44)
                            .disabled(model.isUpdatingUserID != nil)
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Section("Could not update people") {
                    Text(errorMessage)
                    Button("Reload following") { Task { await model.loadFollowing() } }
                        .frame(minHeight: 44)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
