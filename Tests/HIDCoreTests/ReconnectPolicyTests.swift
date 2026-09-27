import XCTest
@testable import HIDCore

final class ReconnectPolicyTests: XCTestCase {
    func testDelaysGrowExponentiallyUpToCap() {
        var policy = ReconnectPolicy(initialDelay: 2, maximumDelay: 30)
        XCTAssertEqual(policy.nextDelay(), 2)
        XCTAssertEqual(policy.nextDelay(), 4)
        XCTAssertEqual(policy.nextDelay(), 8)
        XCTAssertEqual(policy.nextDelay(), 16)
        XCTAssertEqual(policy.nextDelay(), 30)
        XCTAssertEqual(policy.nextDelay(), 30)
    }

    func testResetStartsOverAfterSuccess() {
        var policy = ReconnectPolicy(initialDelay: 2, maximumDelay: 30)
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        policy.reset()
        XCTAssertEqual(policy.nextDelay(), 2)
        XCTAssertEqual(policy.attempt, 1)
    }

    func testAttemptCountTracksScheduledRetries() {
        var policy = ReconnectPolicy()
        XCTAssertEqual(policy.attempt, 0)
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        XCTAssertEqual(policy.attempt, 2)
    }
}

final class ReconnectPolicyLimitTests: XCTestCase {
    func testStopsHandingOutDelaysAfterTheAttemptLimit() {
        var policy = ReconnectPolicy(initialDelay: 1, maximumDelay: 4, maximumAttempts: 3)
        XCTAssertNotNil(policy.nextDelayIfAllowed())
        XCTAssertNotNil(policy.nextDelayIfAllowed())
        XCTAssertNotNil(policy.nextDelayIfAllowed())
        XCTAssertTrue(policy.isExhausted)
        XCTAssertNil(policy.nextDelayIfAllowed())
    }

    func testResetLiftsTheLimit() {
        var policy = ReconnectPolicy(initialDelay: 1, maximumDelay: 4, maximumAttempts: 1)
        _ = policy.nextDelayIfAllowed()
        XCTAssertTrue(policy.isExhausted)
        policy.reset()
        XCTAssertFalse(policy.isExhausted)
        XCTAssertEqual(policy.nextDelayIfAllowed(), 1)
    }
}
