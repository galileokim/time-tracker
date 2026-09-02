// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeTracker",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TimeTrackerCore", targets: ["TimeTrackerCore"]),
    ],
    targets: [
        .target(name: "TimeTrackerCore", sources: ["TimerEngine.swift", "TimerModels.swift", "TimerStore.swift", "APIClient.swift", "TokenStore.swift"]),
        .testTarget(name: "TimeTrackerCoreTests", dependencies: ["TimeTrackerCore"]),
    ]
)
