    import SwiftData
import SwiftUI
import Network
import WidgetKit

@main
struct TimeTrackerApp: App {
    private let container: ModelContainer
    private let api: TrackerAPIClient
    private let tokenStore: KeychainTokenStore

    init() {
        let schema = Schema([StoredTimer.self, StoredActivityLog.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        container = try! ModelContainer(for: schema, configurations: [configuration])
        let apiURL = URL(string: "http://127.0.0.1:3000")!
        api = TrackerAPIClient(baseURL: apiURL)
        tokenStore = KeychainTokenStore()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(api: api, tokenStore: tokenStore)
                .modelContainer(container)
        }
    }
}

@MainActor
@Observable
final class TimerHomeModel {
    private let modelContext: ModelContext
    private let api: TrackerAPIClient
    private let liveActivity: LiveActivityController
    private let tokenProvider: @Sendable () async -> String?
    private let userID: UUID
    private let onAuthenticationExpired: (() -> Void)?
    private(set) var runningTimer: RunningTimer?
    private(set) var pendingLogCount = 0
    private(set) var syncInProgress = false
    private(set) var lastSavedDurationSeconds: Int?
    private(set) var lastSaveRequiresAuthentication = false
    private(set) var activityState: TimerActivityAttributes.ContentState?
    var selectedCategoryID: UUID?
    var newCategoryName = ""
    var visibility: ActivityVisibility = .public
    var errorMessage: String?
    private(set) var completedLogs: [LocalActivityLog] = []
    private(set) var recordedLogs: [LocalActivityLog] = []
    private(set) var categories: [APICategory] = []
    private(set) var isCreatingCategory = false

    init(
        modelContext: ModelContext,
        api: TrackerAPIClient,
        liveActivity: LiveActivityController,
        userID: UUID,
        tokenProvider: @escaping @Sendable () async -> String?,
        onAuthenticationExpired: (() -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.api = api
        self.liveActivity = liveActivity
        self.userID = userID
        self.tokenProvider = tokenProvider
        self.onAuthenticationExpired = onAuthenticationExpired
        refresh()
        refreshProductivityWidget()
    }

    private var accountStore: AccountScopedTimerStore {
        AccountScopedTimerStore(store: SwiftDataTimerStore(modelContext: modelContext), userID: userID)
    }

    func start(at date: Date = .now) {
        do {
            guard let category = categories.first(where: { $0.id == selectedCategoryID }) else {
                errorMessage = "Choose or add a category before starting."
                return
            }
            let timer = try accountStore.start(
                userID: userID,
                title: category.name,
                notes: nil,
                categoryIDs: [category.id],
                visibility: visibility,
                startedAt: date
            )
            runningTimer = timer
            selectedCategoryID = nil
            lastSavedDurationSeconds = nil
            lastSaveRequiresAuthentication = false
            errorMessage = nil
            Task {
                await liveActivity.start(for: timer)
                activityState = liveActivity.currentActivityState()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop(at date: Date = .now) {
        guard let runningTimer else { return }
        do {
            let timerID = runningTimer.id
            let log = try accountStore.stop(timerID: timerID, userID: userID, endedAt: date)
            lastSavedDurationSeconds = log.durationSeconds
            lastSaveRequiresAuthentication = false
            refresh()
            refreshProductivityWidget()
            errorMessage = nil
            Task {
                await liveActivity.end(timerID: timerID)
                activityState = nil
                await synchronize()
            }
        } catch {
            errorMessage = "Timer could not be saved: \(error.localizedDescription)"
        }
    }

    func refresh() {
        do {
            let store = accountStore
            runningTimer = try store.currentTimer(userID: userID)
            pendingLogCount = try modelContext.fetchCount(FetchDescriptor<StoredActivityLog>(predicate: #Predicate { $0.userID == userID && ($0.syncStateRawValue == "pending" || $0.syncStateRawValue == "syncing") }))
            completedLogs = try store.completedLogs(userID: userID)
            recordedLogs = try store.allLogs(userID: userID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        Task {
            await liveActivity.restoreRunningTimer(runningTimer)
            activityState = liveActivity.currentActivityState()
        }
    }

    func synchronize() async {
        guard !syncInProgress, let token = await tokenProvider() else { return }
        syncInProgress = true
        defer { syncInProgress = false }
        do {
            let worker = OfflineSyncWorker(store: accountStore, api: api, userID: userID) { token }
            let report = try await worker.synchronize()
            refresh()
            refreshProductivityWidget()
            if !report.failedKeys.isEmpty {
                let retryableLogs = try accountStore.pendingLogs(userID: userID)
                let details = retryableLogs.compactMap(\.lastSyncError).first
                errorMessage = if let details {
                    "\(report.failedKeys.count) saved log(s) could not sync: \(details)"
                } else {
                    "\(report.failedKeys.count) saved log(s) could not sync. They remain on this device; tap Sync now to retry."
                }
                refreshPendingLogCount()
            }
            await reloadCategories(token: token)
        } catch let error as APIClientError {
            if case .server(401, _) = error {
                errorMessage = "Session expired. Sign in again to sync the saved timer."
                lastSaveRequiresAuthentication = true
                onAuthenticationExpired?()
            } else {
                errorMessage = "Sync could not start. Your logs remain saved on this device. \(error.localizedDescription)"
            }
            refreshPendingLogCount()
        } catch {
            errorMessage = "Sync could not start. Your logs remain saved on this device. \(error.localizedDescription)"
            refreshPendingLogCount()
        }
    }

    private func refreshPendingLogCount() {
        do {
            pendingLogCount = try modelContext.fetchCount(FetchDescriptor<StoredActivityLog>(predicate: #Predicate { $0.userID == userID && ($0.syncStateRawValue == "pending" || $0.syncStateRawValue == "syncing") }))
        } catch {
            errorMessage = "Saved logs are unavailable: \(error.localizedDescription)"
        }
    }

    private func refreshProductivityWidget() {
        let summary = ProductivitySummary(logs: completedLogs.map(\.productivitySummaryLog))
        let defaults = UserDefaults(suiteName: WidgetSummaryStorage.sharedGroupID)
        WidgetSummaryStorage.publish(summary, for: userID, to: defaults)
        WidgetCenter.shared.reloadTimelines(ofKind: "ProductivityWidget")
    }

    func addCategory() async {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter a category name."
            return
        }
        guard let token = await tokenProvider() else {
            errorMessage = "Sign in again to add a category."
            return
        }
        isCreatingCategory = true
        defer { isCreatingCategory = false }
        do {
            let category = try await api.createCategory(name: name, accessToken: token)
            categories.append(category)
            selectedCategoryID = category.id
            newCategoryName = ""
            errorMessage = nil
        } catch ProfileClientError.duplicateCategory {
            errorMessage = "That category already exists. Choose it from the list."
        } catch {
            errorMessage = "Category could not be added. Check your connection and try again."
        }
    }

    func reloadCategories(token: String) async {
        do {
            categories = try await api.categories(accessToken: token)
            if selectedCategoryID == nil {
                selectedCategoryID = categories.first?.id
            }
        } catch {
            errorMessage = "Categories could not be refreshed."
        }
    }
}

@MainActor
@Observable
final class AuthSession {
    private let api: TrackerAPIClient
    private let tokenStore: KeychainTokenStore
    private let liveActivity: LiveActivityController
    private(set) var accessToken: String?
    private(set) var user: APIUser?
    private(set) var isLoading = false
    var errorMessage: String?

    init(api: TrackerAPIClient, tokenStore: KeychainTokenStore, liveActivity: LiveActivityController) {
        self.api = api
        self.tokenStore = tokenStore
        self.liveActivity = liveActivity
        do {
            self.accessToken = try tokenStore.read()
        } catch {
            self.accessToken = nil
            self.errorMessage = "Could not read the saved session. Sign in again."
        }
    }

    func login(username: String, password: String) async {
        await authenticate {
            let tokens = try await api.login(username: username, password: password)
            try await accept(tokens.accessToken)
        }
    }

    func register(username: String, displayName: String, email: String, password: String) async {
        await authenticate {
            _ = try await api.register(username: username, displayName: displayName, email: email, password: password)
            let tokens = try await api.login(username: username, password: password)
            try await accept(tokens.accessToken)
        }
    }

    func updateDisplayName(_ displayName: String) {
        guard var user else { return }
        user.displayName = displayName
        self.user = user
    }

    func signOut() {
        Task { await liveActivity.endAll() }
        WidgetSummaryStorage.clearActiveUser(from: UserDefaults(suiteName: WidgetSummaryStorage.sharedGroupID))
        WidgetCenter.shared.reloadTimelines(ofKind: "ProductivityWidget")
        do {
            try tokenStore.delete()
            accessToken = nil
            user = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreSession() async {
        guard let accessToken else { return }
        do {
            user = try await api.profile(accessToken: accessToken)
        } catch {
            signOut()
            errorMessage = "Your session expired. Sign in again."
        }
    }

    private func accept(_ token: String) async throws {
        do {
            let user = try await api.profile(accessToken: token)
            try tokenStore.save(token)
            accessToken = token
            self.user = user
        } catch {
            try? tokenStore.delete()
            accessToken = nil
            user = nil
            throw error
        }
    }

    private func authenticate(_ operation: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await operation()
        } catch let error as APIClientError {
            switch error {
            case .server(let statusCode, let code):
                if code == "INVALID_CREDENTIALS" {
                    errorMessage = "Username or password is incorrect."
                } else if code == "INVALID_REQUEST" {
                    errorMessage = "Check the fields: usernames need 3 to 50 letters, numbers, dots, underscores, or hyphens; password cannot be empty; and email must be valid."
                } else if statusCode == 409 {
                    errorMessage = "That username or email is already in use."
                } else {
                    errorMessage = "Request failed (\(statusCode), \(code)). Check the fields and try again."
                }
            case .invalidResponse, .decoding: errorMessage = "The server returned an unreadable response."
            }
        } catch {
            errorMessage = "Could not connect. Check your network and try again."
        }
    }
}

struct AppRootView: View {
    let api: TrackerAPIClient
    let tokenStore: KeychainTokenStore
    @State private var session: AuthSession?
    @State private var liveActivity = LiveActivityController()

    var body: some View {
        Group {
            if let session {
                if let token = session.accessToken, session.user != nil {
                    TimerHomeView(api: api, token: token, user: session.user!, liveActivity: liveActivity, onSignOut: session.signOut, onDisplayNameChanged: session.updateDisplayName)
                } else if session.accessToken != nil {
                    ProgressView("Restoring your session")
                        .task { await session.restoreSession() }
                } else {
                    AuthenticationView(session: session)
                }
            } else {
                ProgressView("Opening Time Tracker")
                    .task { session = AuthSession(api: api, tokenStore: tokenStore, liveActivity: liveActivity) }
            }
        }
    }
}

struct AuthenticationView: View {
    let session: AuthSession
    @State private var isRegistering = false
    @State private var username = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                Section("Account") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if isRegistering {
                        TextField("Display name", text: $displayName)
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                    }
                    SecureField("Password", text: $password)
                    if isRegistering {
                        Text("Password is required.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .id("registration-guidance")
                    }
                }
                .textFieldStyle(.roundedBorder)
                Section {
                    if !isRegistering {
                        Button("Sign in") {
                            Task { await session.login(username: username, password: password) }
                        }
                        .disabled(session.isLoading)
                    }

                    Button(isRegistering ? "I already have an account" : "Create an account") {
                        isRegistering.toggle()
                        session.errorMessage = nil
                    }
                    .font(.footnote)
                }
                if session.isLoading {
                    ProgressView("Connecting")
                }
                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: username) { _, _ in session.errorMessage = nil }
                .onChange(of: password) { _, _ in session.errorMessage = nil }
                .onChange(of: displayName) { _, _ in session.errorMessage = nil }
                .onChange(of: email) { _, _ in session.errorMessage = nil }
                .onChange(of: isRegistering) { _, _ in
                    session.errorMessage = nil
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if isRegistering {
                        Button {
                            Task {
                                await session.register(username: username, displayName: displayName, email: email, password: password)
                            }
                        } label: {
                            if session.isLoading {
                                ProgressView("Creating account")
                                    .frame(maxWidth: .infinity, minHeight: 50)
                            } else {
                                Text("Create account")
                                    .frame(maxWidth: .infinity, minHeight: 50)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.isLoading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        .background(.bar)
                    }
                }
                .navigationTitle(isRegistering ? "Create account" : "Welcome back")
            }
        }
    }
}

private enum TrackerTab: Hashable {
    case log
    case timer
    case analytics
    case profile
}

struct TimerHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TimerHomeModel?
    @State private var selectedTab = TrackerTab.timer
    @State private var now = Date.now
    @State private var showTimerSaveAlert = false
    let api: TrackerAPIClient
    let token: String
    let user: APIUser
    let liveActivity: LiveActivityController
    var onSignOut: () -> Void = {}
    var onDisplayNameChanged: (String) -> Void = { _ in }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView("Opening your timer")
                    .task {
                        let timerModel = TimerHomeModel(modelContext: modelContext, api: api, liveActivity: liveActivity, userID: user.id, tokenProvider: { token }) {
                            onSignOut()
                        }
                        model = timerModel
                        await timerModel.synchronize()
                        await timerModel.reloadCategories(token: token)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
        .onChange(of: token) { oldToken, newToken in
            if oldToken != newToken {
                Task { await liveActivity.endAll() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model?.synchronize() }
            }
        }
        .alert("Timer could not be saved", isPresented: $showTimerSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model?.errorMessage ?? "Try stopping the timer again.")
        }
        .onChange(of: model?.errorMessage) { _, message in
            if message?.hasPrefix("Timer could not be saved:") == true {
                showTimerSaveAlert = true
            }
        }
    }

    @ViewBuilder
    private func content(_ model: TimerHomeModel) -> some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ActivityLogView(logs: model.recordedLogs, api: api, token: token)
            }
            .tabItem {
                Label("Log", systemImage: "list.bullet.rectangle")
            }
            .tag(TrackerTab.log)

            NavigationStack {
                timerContent(model)
            }
            .tabItem {
                Label("Timer", systemImage: "timer")
            }
            .tag(TrackerTab.timer)

            NavigationStack {
                ProductivitySummaryView(
                    summary: ProductivitySummary(logs: model.recordedLogs.map(\.productivitySummaryLog), now: now),
                    hasRecordedLogs: !model.recordedLogs.isEmpty,
                    categories: model.categories
                )
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Analytics")
            }
            .tabItem {
                Label("Analytics", systemImage: "chart.bar")
            }
            .tag(TrackerTab.analytics)

            NavigationStack {
                ProfileAndCategoriesView(api: api, token: token, user: user, onDisplayNameChanged: onDisplayNameChanged)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Sign out", action: onSignOut)
                        }
                    }
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(TrackerTab.profile)
        }
        .tint(.orange)
    }

    private func timerContent(_ model: TimerHomeModel) -> some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Time Tracker")
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let timer = model.runningTimer {
                        runningTimer(timer, model: model)
                    } else {
                        timerForm(model)
                    }

                    if let duration = model.lastSavedDurationSeconds {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Saved \(Duration.seconds(duration), format: .time(pattern: .hourMinuteSecond)) on this device", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                            if model.lastSaveRequiresAuthentication {
                                Text("Sign in again, then tap Sync now to upload this log.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button("Sign in again", action: onSignOut)
                                    .frame(minHeight: 44)
                            } else if model.pendingLogCount > 0 {
                                Text("It will appear in your recorded totals after syncing.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button(model.syncInProgress ? "Syncing" : "Sync now") {
                                    Task { await model.synchronize() }
                                }
                                .disabled(model.syncInProgress)
                                .frame(minHeight: 44)
                            }
                        }
                    }

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let state = model.activityState {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Live Activity preview")
                                .font(.headline)
                            LiveTimerLockScreenView(state: state)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }

                    if model.pendingLogCount > 0 && model.lastSavedDurationSeconds == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(model.pendingLogCount) saved logs waiting to sync")
                                .font(.subheadline)
                            Button(model.syncInProgress ? "Syncing" : "Sync now") {
                                Task { await model.synchronize() }
                            }
                            .disabled(model.syncInProgress)
                            .frame(minHeight: 44)
                        }
                    }

                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
    }

    private func runningTimer(_ timer: RunningTimer, model: TimerHomeModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Timer running")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(model.categories.first(where: { $0.id == timer.categoryIDs.first })?.name ?? timer.title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(Duration.seconds(timer.elapsedSeconds(at: now)), format: .time(pattern: .hourMinuteSecond))
                .font(.system(size: 44, weight: .regular, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .accessibilityLabel("Elapsed time")
            HStack(spacing: 8) {
                Text(timer.visibility == .friendsOnly ? "Friends only" : timer.visibility.rawValue.capitalized)
                if !timer.categoryIDs.isEmpty {
                    Text("·")
                    Text(timer.categoryIDs.compactMap { id in model.categories.first(where: { $0.id == id })?.name }.joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(action: { model.stop() }) {
                Label("Stop and save", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func timerForm(_ model: TimerHomeModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose an activity")
                .font(.headline)

            if model.categories.isEmpty {
                Text("Add a category to get started, such as a course, reading, exercise, or project.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Category", selection: Binding(
                    get: { model.selectedCategoryID },
                    set: { model.selectedCategoryID = $0 }
                )) {
                    Text("Choose a category").tag(Optional<UUID>.none)
                    ForEach(model.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .accessibilityLabel("Activity category")
            }

            HStack(spacing: 10) {
                TextField("Add a category", text: Binding(
                    get: { model.newCategoryName },
                    set: { model.newCategoryName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { Task { await model.addCategory() } }
                .frame(minHeight: 44)

                Button(model.isCreatingCategory ? "Adding" : "Add") {
                    Task { await model.addCategory() }
                }
                .frame(minWidth: 56, minHeight: 44)
                .disabled(model.isCreatingCategory || model.newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Picker("Visibility", selection: Binding(
                get: { model.visibility },
                set: { model.visibility = $0 }
            )) {
                Text("Public").tag(ActivityVisibility.public)
                Text("Friends").tag(ActivityVisibility.friendsOnly)
                Text("Private").tag(ActivityVisibility.private)
            }
            .pickerStyle(.segmented)

            Button(action: { model.start() }) {
                Label("Start timer", systemImage: "record.circle")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedCategoryID == nil || model.isCreatingCategory)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
