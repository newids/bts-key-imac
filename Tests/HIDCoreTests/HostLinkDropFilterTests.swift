import XCTest
@testable import HIDCore

final class HostLinkDropFilterTests: XCTestCase {
    func testADropWithNoLinkOfOursBehindItIsTheHosts() {
        var filter = HostLinkDropFilter()
        XCTAssertTrue(filter.isHostLinkDrop(at: 100))
    }

    func testTheDropOfTheLinkThisAppJustReleasedIsNotACue() {
        var filter = HostLinkDropFilter()
        filter.expectOwnDrop(at: 100)
        XCTAssertFalse(filter.isHostLinkDrop(at: 100.2))
    }

    func testOnlyOneDropIsAttributedToTheAppsOwnLink() {
        var filter = HostLinkDropFilter()
        filter.expectOwnDrop(at: 100)
        _ = filter.isHostLinkDrop(at: 100.2)
        XCTAssertTrue(filter.isHostLinkDrop(at: 118), "the next drop is a link the host brought up")
    }

    func testAnExpectationThatWasNeverMetExpires() {
        // The link was already gone when the app released it, so no notification came for it.
        var filter = HostLinkDropFilter()
        filter.expectOwnDrop(at: 100)
        XCTAssertTrue(filter.isHostLinkDrop(at: 100 + HostLinkDropFilter.window + 1))
    }
}
