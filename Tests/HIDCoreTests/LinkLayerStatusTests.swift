import XCTest
@testable import HIDCore

final class LinkLayerStatusTests: XCTestCase {
    func testLayersAreReportedBottomUp() {
        XCTAssertEqual(LinkLayerStatus(isPaired: false, isBasebandUp: false, areHIDChannelsOpen: false), .notPaired)
        XCTAssertEqual(LinkLayerStatus(isPaired: true, isBasebandUp: false, areHIDChannelsOpen: false), .pairedOnly)
        XCTAssertEqual(LinkLayerStatus(isPaired: true, isBasebandUp: true, areHIDChannelsOpen: false), .basebandOnly)
        XCTAssertEqual(LinkLayerStatus(isPaired: true, isBasebandUp: true, areHIDChannelsOpen: true), .hidReady)
    }

    func testOpenChannelsProveTheLinkEvenWhenTheSystemFlagLags() {
        // isConnected() stays false for links this app opened (connection audit 6).
        XCTAssertEqual(LinkLayerStatus(isPaired: true, isBasebandUp: false, areHIDChannelsOpen: true), .hidReady)
    }

    func testSystemSaysConnectedButKeyboardIsNotUsableYet() {
        let status = LinkLayerStatus(isPaired: true, isBasebandUp: true, areHIDChannelsOpen: false)
        XCTAssertTrue(status.looksConnectedInSystemSettings)
        XCTAssertFalse(status.canType)
    }
}
