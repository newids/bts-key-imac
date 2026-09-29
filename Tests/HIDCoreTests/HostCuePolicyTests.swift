import XCTest
@testable import HIDCore

final class HostCuePolicyTests: XCTestCase {
    func testHonorsOneCueThenIgnoresAHostThatKeepsPaging() {
        var policy = HostCuePolicy()
        XCTAssertTrue(policy.shouldHonorCue())
        XCTAssertFalse(policy.shouldHonorCue())
        XCTAssertFalse(policy.shouldHonorCue())
    }

    func testASuccessfulLinkOrAUserRequestRefillsTheAllowance() {
        var policy = HostCuePolicy()
        _ = policy.shouldHonorCue()
        policy.reset()
        XCTAssertTrue(policy.shouldHonorCue())
    }

    func testAllowanceIsConfigurable() {
        var policy = HostCuePolicy(allowance: 2)
        XCTAssertTrue(policy.shouldHonorCue())
        XCTAssertTrue(policy.shouldHonorCue())
        XCTAssertFalse(policy.shouldHonorCue())
        XCTAssertTrue(policy.isExhausted)
    }
}
