import XCTest
@testable import HIDCore

final class HIDChannelRoleTests: XCTestCase {
    func testRolesComeFromThePSMNotTheObject() {
        XCTAssertEqual(HIDChannelRole(psm: 0x11), .control)
        XCTAssertEqual(HIDChannelRole(psm: 0x13), .interrupt)
        XCTAssertNil(HIDChannelRole(psm: 0x01))
    }
}
