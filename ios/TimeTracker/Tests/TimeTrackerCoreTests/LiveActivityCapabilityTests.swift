import Testing
@testable import TimeTrackerCore

struct LiveActivityCapabilityTests {
    @Test func requestsActivityOnlyWhenSystemAllowsIt() {
        #expect(LiveActivityCapability.shouldRequestActivity(activitiesEnabled: true))
        #expect(!LiveActivityCapability.shouldRequestActivity(activitiesEnabled: false))
    }
}
