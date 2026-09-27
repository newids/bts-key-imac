import XCTest
@testable import HIDCore

final class MacKeycodeMapTests: XCTestCase {
    func testLettersAndCommonKeys() {
        XCTAssertEqual(MacKeycodeMap.usage(forVirtualKey: 0), 0x04)   // A
        XCTAssertEqual(MacKeycodeMap.usage(forVirtualKey: 40), 0x0E)  // K
        XCTAssertEqual(MacKeycodeMap.usage(forVirtualKey: 36), 0x28)  // Return
        XCTAssertEqual(MacKeycodeMap.usage(forVirtualKey: 49), 0x2C)  // Space
        XCTAssertEqual(MacKeycodeMap.usage(forVirtualKey: 51), 0x2A)  // Backspace
        XCTAssertEqual(MacKeycodeMap.usage(forVirtualKey: 53), 0x29)  // Escape
        XCTAssertEqual(MacKeycodeMap.usage(forVirtualKey: 126), 0x52) // Up arrow
    }

    func testModifierKeysMapToModifierUsages() {
        XCTAssertEqual(MacKeycodeMap.usage(forVirtualKey: 55), 0xE3)  // Command
        XCTAssertEqual(MacKeycodeMap.usage(forVirtualKey: 54), 0xE7)  // Right Command
        XCTAssertEqual(MacKeycodeMap.usage(forVirtualKey: 57), 0x39)  // Caps Lock
    }

    func testUnmappedKeysReturnNil() {
        XCTAssertNil(MacKeycodeMap.usage(forVirtualKey: 63))  // Fn
        XCTAssertNil(MacKeycodeMap.usage(forVirtualKey: 999))
    }
}
