// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeTracker",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TimeTrackerCore", targets: ["TimeTrackerCore"]),
    ],
    targets: [
        .target(name: "TimeTrackerCore", exclude: ["TimerActivityAttributes.swift"], sources: ["TimerEngine.swift", "TimerModels.swift", "TimerStore.swift", "APIClient.swift", "TokenStore.swift", "SyncWorker.swift", "ConnectivityMonitor.swift"]),
        .testTarget(name: "TimeTrackerCoreTests", dependencies: ["TimeTrackerCore"], sources: ["TimerEngineTests.swift", "APIClientTests.swift", "SyncWorkerTests.swift"]),
    ]
)
