import SwiftData
import SwiftUI
import Network

@main
struct TimeTrackerApp: App {
    private let container: ModelContainer
    private let api: TrackerAPIClient
    private let tokenStore: KeychainTokenStore

    init() {
        let schema = Schema([StoredTimer.self, StoredActivityLog.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        container = try! ModelContainer(for: schema, configurations: [configuration])
        let apiURL = URL(string: ProcessInfo.processInfo.environment["TRACKER_API_URL"] ?? "http://localhost:3000")!
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
    private let engine = TimerEngine()
    private let liveActivity: LiveActivityController
    private let tokenProvider: @Sendable () async -> String?
    private(set) var runningTimer: RunningTimer?
    private(set) var pendingLogCount = 0
    private(set) var syncInProgress = false
    private(set) var activityState: TimerActivityAttributes.ContentState?
    var title = ""
    var errorMessage: String?
    private(set) var completedLogs: [LocalActivityLog] = []
    private(set) var categories: [APICategory] = []

    init(
        modelContext: ModelContext,
        api: TrackerAPIClient,
        liveActivity: LiveActivityController,
        tokenProvider: @escaping @Sendable () async -> String?
    ) {
        self.modelContext = modelContext
        self.api = api
        self.liveActivity = liveActivity
        self.tokenProvider = tokenProvider
        refresh()
    }

    func start(at date: Date = .now) {
        do {
            let timer = try engine.start(existing: runningTimer, title: title, notes: nil, categoryIDs: [], visibility: .public, at: date)
            modelContext.insert(try StoredTimer(timer: timer))
            try modelContext.save()
            runningTimer = timer
            title = ""
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
            let log = try engine.stop(timer: runningTimer, at: date)
            let descriptor = FetchDescriptor<StoredTimer>(predicate: #Predicate { $0.id == timerID })
            if let storedTimer = try modelContext.fetch(descriptor).first {
                modelContext.delete(storedTimer)
            }
            modelContext.insert(try StoredActivityLog(log: log))
            try modelContext.save()
            refresh()
            errorMessage = nil
            Task {
                await liveActivity.end(timerID: timerID)
                activityState = nil
                await synchronize()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() {
        do {
            runningTimer = try modelContext.fetch(FetchDescriptor<StoredTimer>(sortBy: [SortDescriptor(\.startedAt)])).first?.runningTimer
            pendingLogCount = try modelContext.fetchCount(FetchDescriptor<StoredActivityLog>(predicate: #Predicate { $0.syncStateRawValue == "pending" || $0.syncStateRawValue == "syncing" }))
            completedLogs = try SwiftDataTimerStore(modelContext: modelContext).completedLogs()
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
            let store = SwiftDataTimerStore(modelContext: modelContext)
            let worker = OfflineSyncWorker(store: store, api: api) { token }
            _ = try await worker.synchronize()
            refresh()
            await reloadCategories(token: token)
        } catch {
            errorMessage = "Sync could not start. Your logs remain saved on this device."
        }
    }

    func reloadCategories(token: String) async {
        do {
            categories = try await api.categories(accessToken: token)
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
    private(set) var accessToken: String?
    private(set) var user: APIUser?
    private(set) var isLoading = false
    var errorMessage: String?

    init(api: TrackerAPIClient, tokenStore: KeychainTokenStore) {
        self.api = api
        self.tokenStore = tokenStore
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

    func signOut() {
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
            case .server(_, let code): errorMessage = code == "INVALID_CREDENTIALS" ? "Username or password is incorrect." : "Sign-in failed (\(code))."
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

    var body: some View {
        Group {
            if let session {
                if let token = session.accessToken, session.user != nil {
                    TimerHomeView(api: api, token: token, user: session.user!, onSignOut: session.signOut)
                } else if session.accessToken != nil {
                    ProgressView("Restoring your session")
                        .task { await session.restoreSession() }
                } else {
                    AuthenticationView(session: session)
                }
            } else {
                ProgressView("Opening Time Tracker")
                    .task { session = AuthSession(api: api, tokenStore: tokenStore) }
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
                }
                Section {
                    Button(isRegistering ? "Create account" : "Sign in") {
                        Task {
                            if isRegistering {
                                await session.register(username: username, displayName: displayName, email: email, password: password)
                            } else {
                                await session.login(username: username, password: password)
                            }
                        }
                    }
                    .disabled(session.isLoading)

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
                }
            }
            .navigationTitle(isRegistering ? "Create account" : "Welcome back")
        }
    }
}

struct TimerHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TimerHomeModel?
    @State private var now = Date.now
    @State private var liveActivity = LiveActivityController()
    let api: TrackerAPIClient
    let token: String
    let user: APIUser
    var onSignOut: () -> Void = {}

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView("Opening your timer")
                    .task {
                        let timerModel = TimerHomeModel(modelContext: modelContext, api: api, liveActivity: liveActivity) { token }
                        model = timerModel
                        await timerModel.synchronize()
                        await timerModel.reloadCategories(token: token)
                    }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model?.synchronize() }
            }
        }
    }

    @ViewBuilder
    private func content(_ model: TimerHomeModel) -> some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack {
                    Text("Time Tracker")
                        .font(.largeTitle.weight(.semibold))
                    Spacer()
                    NavigationLink("Profile") {
                        ProfileAndCategoriesView(api: api, token: token, user: user)
                    }
                    NavigationLink("Activity") {
                        SocialFeedView(api: api, token: token)
                    }
                    Button("Sign out", action: onSignOut)
                        .font(.subheadline)
                }

            if let timer = model.runningTimer {
                VStack(alignment: .leading, spacing: 12) {
                    Text(timer.title)
                        .font(.title2.weight(.medium))
                    Text(Duration.seconds(timer.elapsedSeconds(at: now)), format: .time(pattern: .hourMinuteSecond))
                        .font(.system(size: 48, weight: .regular, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: { model.stop() }) {
                    Text("Stop timer")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                TextField("What are you working on?", text: Binding(
                    get: { model.title },
                    set: { model.title = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.sentences)

                Button(action: { model.start() }) {
                    Text("Start timer")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ProductivitySummaryView(
                summary: ProductivitySummary(logs: model.completedLogs, now: now),
                categories: model.categories
            )

            if let state = model.activityState {
                LiveTimerLockScreenView(state: state)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }

            if model.pendingLogCount > 0 {
                HStack {
                    Text("\(model.pendingLogCount) logs waiting to sync")
                    Spacer()
                    Button(model.syncInProgress ? "Syncing" : "Sync now") {
                        Task { await model.synchronize() }
                    }
                    .disabled(model.syncInProgress)
                }
                .font(.subheadline)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
                Spacer(minLength: 0)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
