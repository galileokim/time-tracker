import SwiftUI

@MainActor
@Observable
final class ProfileAndCategoriesModel {
    enum Operation {
        case loadCategories
        case saveProfile
        case createCategory

        var retryTitle: String {
            switch self {
            case .loadCategories: "Retry loading categories"
            case .saveProfile: "Retry saving profile"
            case .createCategory: "Retry adding category"
            }
        }
    }

    let categories: CategoryStore
    private let api: TrackerAPIClient
    private let token: String
    private let onDisplayNameChanged: (String) -> Void
    private(set) var profile: APIUser
    private(set) var isSavingProfile = false
    private(set) var failedOperation: Operation?
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    var displayName: String
    var categoryName = ""

    init(
        api: TrackerAPIClient,
        token: String,
        user: APIUser,
        categories: CategoryStore,
        onDisplayNameChanged: @escaping (String) -> Void
    ) {
        self.api = api
        self.token = token
        self.categories = categories
        self.onDisplayNameChanged = onDisplayNameChanged
        profile = user
        displayName = user.displayName
    }

    var isBusy: Bool {
        categories.isLoading || categories.isCreating || isSavingProfile
    }

    var canAddCategory: Bool {
        !categories.isCreating && !trimmedCategoryName.isEmpty
    }

    private var trimmedCategoryName: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func loadCategories() async {
        beginOperation()
        do {
            try await categories.reload()
        } catch {
            fail(.loadCategories, "Categories could not be loaded. Check your connection and try again.")
        }
    }

    func saveProfile() async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Display name cannot be empty."
            return
        }
        beginOperation()
        isSavingProfile = true
        defer { isSavingProfile = false }
        do {
            profile = try await api.updateProfile(displayName: trimmed, accessToken: token)
            displayName = profile.displayName
            onDisplayNameChanged(profile.displayName)
            successMessage = "Profile saved."
        } catch {
            fail(.saveProfile, "Profile could not be saved. Check your connection and try again.")
        }
    }

    func addCategory() async {
        let name = trimmedCategoryName
        guard !name.isEmpty else {
            errorMessage = "Enter a category name."
            return
        }
        beginOperation()
        do {
            _ = try await categories.create(named: name)
            categoryName = ""
            successMessage = "Category added."
        } catch ProfileClientError.duplicateCategory {
            fail(.createCategory, "A category with that name already exists.")
        } catch {
            fail(.createCategory, "Category could not be added. Check your connection and try again.")
        }
    }

    func retryFailedOperation() async {
        switch failedOperation {
        case .loadCategories: await loadCategories()
        case .saveProfile: await saveProfile()
        case .createCategory: await addCategory()
        case nil: break
        }
    }

    private func beginOperation() {
        errorMessage = nil
        successMessage = nil
        failedOperation = nil
    }

    private func fail(_ operation: Operation, _ message: String) {
        failedOperation = operation
        errorMessage = message
    }
}

struct ProfileAndCategoriesView: View {
    @State private var model: ProfileAndCategoriesModel

    init(
        api: TrackerAPIClient,
        token: String,
        user: APIUser,
        categories: CategoryStore,
        onDisplayNameChanged: @escaping (String) -> Void
    ) {
        _model = State(initialValue: ProfileAndCategoriesModel(
            api: api,
            token: token,
            user: user,
            categories: categories,
            onDisplayNameChanged: onDisplayNameChanged
        ))
    }

    var body: some View {
        Form {
            Section("Profile") {
                LabeledContent("Username", value: "@\(model.profile.username)")
                LabeledContent("Email", value: model.profile.email)
                TextField("Display name", text: $model.displayName)
                    .textContentType(.name)
                    .submitLabel(.done)
                Button(model.isSavingProfile ? "Saving" : "Save display name") {
                    Task { await model.saveProfile() }
                }
                .disabled(model.isSavingProfile)
            }

            Section("Categories") {
                if model.categories.isLoading && model.categories.categories.isEmpty {
                    ProgressView("Loading categories")
                } else if model.categories.categories.isEmpty {
                    ContentUnavailableView(
                        "No categories yet",
                        systemImage: "tag",
                        description: Text("Add a category to organize your activity.")
                    )
                } else {
                    ForEach(model.categories.categories) { category in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: category.colorHex))
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                            Text(category.name)
                        }
                    }
                }
                HStack(spacing: 12) {
                    TextField("Category name", text: $model.categoryName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { Task { await model.addCategory() } }
                    Button(model.categories.isCreating ? "Adding" : "Add") {
                        Task { await model.addCategory() }
                    }
                    .frame(minWidth: 52, minHeight: 44)
                    .disabled(!model.canAddCategory)
                }
            }

            if let successMessage = model.successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle")
                }
            }
            if let errorMessage = model.errorMessage {
                Section("Could not complete action") {
                    Text(errorMessage)
                    if let operation = model.failedOperation {
                        Button(operation.retryTitle) {
                            Task { await model.retryFailedOperation() }
                        }
                        .frame(minHeight: 44)
                        .disabled(model.isBusy)
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .task { await model.loadCategories() }
    }
}

private extension Color {
    /// Parses `#RRGGBB`; malformed values render black.
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
