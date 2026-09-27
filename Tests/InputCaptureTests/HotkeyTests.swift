import XCTest
import CoreGraphics
@testable import InputCapture

final class HotkeyTests: XCTestCase {
    func testDefaultIsCommandOptionK() {
        let hotkey = Hotkey.default
        XCTAssertEqual(hotkey.keyCode, 40)
        XCTAssertTrue(hotkey.requiresCommand)
        XCTAssertTrue(hotkey.requiresOption)
        XCTAssertFalse(hotkey.requiresControl)
        XCTAssertFalse(hotkey.requiresShift)
        XCTAssertEqual(hotkey.displayString, "⌥⌘K")
    }

    func testMatchesOnlyTheExactChord() {
        let hotkey = Hotkey.default
        XCTAssertTrue(hotkey.matches(keyCode: 40, flags: [.maskCommand, .maskAlternate]))
        XCTAssertFalse(hotkey.matches(keyCode: 40, flags: [.maskCommand, .maskAlternate, .maskControl]))
        XCTAssertFalse(hotkey.matches(keyCode: 40, flags: [.maskCommand]))
        XCTAssertFalse(hotkey.matches(keyCode: 41, flags: [.maskCommand, .maskAlternate]))
    }
}
