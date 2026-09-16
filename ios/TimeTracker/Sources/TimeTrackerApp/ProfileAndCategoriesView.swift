import SwiftUI

@MainActor
@Observable
final class ProfileAndCategoriesModel {
    private let api: TrackerAPIClient
    private let token: String
    private let onDisplayNameChanged: (String) -> Void
    private(set) var profile: APIProfile
    private(set) var categories: [APICategory] = []
    private(set) var isLoading = false
    private(set) var isSavingProfile = false
    private(set) var isCreatingCategory = false
    var displayName: String
    var categoryName = ""
    var errorMessage: String?
    var successMessage: String?

    init(api: TrackerAPIClient, token: String, user: APIUser, onDisplayNameChanged: @escaping (String) -> Void) {
        self.api = api
        self.token = token
        self.onDisplayNameChanged = onDisplayNameChanged
        profile = APIProfile(id: user.id, username: user.username, displayName: user.displayName, email: user.email, avatarUrl: user.avatarUrl)
        displayName = user.displayName
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            categories = try await api.categories(accessToken: token)
        } catch {
            errorMessage = "Categories could not be loaded. Check your connection and try again."
        }
    }

    func saveProfile() async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Display name cannot be empty."
            return
        }
        isSavingProfile = true
        errorMessage = nil
        successMessage = nil
        defer { isSavingProfile = false }
        do {
            profile = try await api.updateProfile(displayName: trimmed, accessToken: token)
            displayName = profile.displayName
            onDisplayNameChanged(profile.displayName)
            successMessage = "Profile saved."
        } catch {
            errorMessage = "Profile could not be saved. Check your connection and try again."
        }
    }

    func addCategory() async {
        let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter a category name."
            return
        }
        isCreatingCategory = true
        errorMessage = nil
        successMessage = nil
        defer { isCreatingCategory = false }
        do {
            let category = try await api.createCategory(name: name, accessToken: token)
            categories.append(category)
            categoryName = ""
            successMessage = "Category added."
        } catch ProfileClientError.duplicateCategory {
            errorMessage = "A category with that name already exists."
        } catch {
            errorMessage = "Category could not be added. Check your connection and try again."
        }
    }
}

struct ProfileAndCategoriesView: View {
    let api: TrackerAPIClient
    let token: String
    let user: APIUser
    var onDisplayNameChanged: (String) -> Void = { _ in }
    @State private var model: ProfileAndCategoriesModel?

    var body: some View {
        Group {
            if let model {
                Form {
                    Section("Profile") {
                        LabeledContent("Username", value: "@\(model.profile.username)")
                        LabeledContent("Email", value: model.profile.email)
                        TextField("Display name", text: Binding(
                            get: { model.displayName },
                            set: { model.displayName = $0 }
                        ))
                            .textContentType(.name)
                            .submitLabel(.done)
                        Button(model.isSavingProfile ? "Saving" : "Save display name") {
                            Task { await model.saveProfile() }
                        }
                        .disabled(model.isSavingProfile)
                    }

                    Section("Categories") {
                        if model.isLoading {
                            ProgressView("Loading categories")
                        } else if model.categories.isEmpty {
                            ContentUnavailableView("No categories yet", systemImage: "tag", description: Text("Add a category to organize your activity.").font(.body))
                        } else {
                            ForEach(model.categories) { category in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color(hex: category.colorHex))
                                        .frame(width: 12, height: 12)
                                        .accessibilityHidden(true)
                                    Text(category.name)
                                    Spacer()
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        HStack(spacing: 12) {
                            TextField("Category name", text: Binding(
                                get: { model.categoryName },
                                set: { model.categoryName = $0 }
                            ))
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit { Task { await model.addCategory() } }
                            Button(model.isCreatingCategory ? "Adding" : "Add") {
                                Task { await model.addCategory() }
                            }
                            .frame(minWidth: 52, minHeight: 44)
                            .disabled(model.isCreatingCategory || model.categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    if let successMessage = model.successMessage {
                        Section {
                            Label(successMessage, systemImage: "checkmark.circle")
                                .foregroundStyle(.primary)
                        }
                    }
                    if let errorMessage = model.errorMessage {
                        Section("Could not save changes") {
                            Text(errorMessage)
                            Button("Retry loading categories") {
                                Task { await model.load() }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
                .navigationTitle("Profile")
                .task { await model.load() }
            } else {
                ProgressView("Opening profile")
                    .task { model = ProfileAndCategoriesModel(api: api, token: token, user: user, onDisplayNameChanged: onDisplayNameChanged) }
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
