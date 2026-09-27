import XCTest
@testable import HIDCore

final class InboundPolicyTests: XCTestCase {
    func testAcceptsAnyPairedHostSoMovingToAnotherIMacJustWorks() {
        XCTAssertTrue(InboundPolicy.shouldAccept(isPaired: true, isPaused: false))
    }

    func testRejectsUnpairedHosts() {
        XCTAssertFalse(InboundPolicy.shouldAccept(isPaired: false, isPaused: false))
    }

    func testRejectsEverythingWhileUserPaused() {
        XCTAssertFalse(InboundPolicy.shouldAccept(isPaired: true, isPaused: true))
    }

    func testNormalizesAddresses() {
        XCTAssertEqual(InboundPolicy.normalize("BB:BB:BB:BB:BB:02"), "bb-bb-bb-bb-bb-02")
        XCTAssertTrue(InboundPolicy.isSameHost("bb-bb-bb-bb-bb-02", "BB:BB:BB:BB:BB:02"))
        XCTAssertFalse(InboundPolicy.isSameHost("aa-aa-aa-aa-aa-01", "BB:BB:BB:BB:BB:02"))
        XCTAssertFalse(InboundPolicy.isSameHost(nil, "BB:BB:BB:BB:BB:02"))
    }
}
