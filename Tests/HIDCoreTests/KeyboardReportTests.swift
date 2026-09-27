import XCTest
@testable import HIDCore

final class KeyboardReportTests: XCTestCase {
    func testEmptyReportIsNineZeroBytes() {
        XCTAssertEqual(KeyboardReport().bytes, [UInt8](repeating: 0, count: 9))
    }

    func testFnIsTheTrailingAppleVendorByte() {
        XCTAssertEqual(KeyboardReport(fn: true).bytes, [0, 0, 0, 0, 0, 0, 0, 0, 1])
    }

    func testModifiersAndKeysAreEncodedInOrder() {
        let report = KeyboardReport(modifiers: [.leftShift, .leftGUI], keys: [0x04, 0x05])
        XCTAssertEqual(report.bytes, [0x0A, 0x00, 0x04, 0x05, 0, 0, 0, 0, 0])
    }

    func testMoreThanSixKeysIsTruncatedToSix() {
        let report = KeyboardReport(modifiers: [], keys: [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(report.bytes.count, 9)
        XCTAssertEqual(Array(report.bytes[2..<8]), [1, 2, 3, 4, 5, 6])
    }

    func testStatePressAndReleaseProducesReports() {
        var state = KeyboardState()
        state.press(0x04)
        state.press(0x05)
        XCTAssertEqual(state.report.keys, [0x04, 0x05])
        state.release(0x04)
        XCTAssertEqual(state.report.keys, [0x05])
        state.release(0x05)
        XCTAssertEqual(state.report, KeyboardReport())
    }

    func testStateIgnoresDuplicatePress() {
        var state = KeyboardState()
        state.press(0x04)
        state.press(0x04)
        XCTAssertEqual(state.report.keys, [0x04])
    }

    func testStateAllUpClearsKeysAndModifiers() {
        var state = KeyboardState()
        state.press(0x04)
        state.modifiers = [.leftControl]
        state.allUp()
        XCTAssertEqual(state.report, KeyboardReport())
        XCTAssertTrue(state.isIdle)
    }

    func testModifierUsagesMapToBits() {
        XCTAssertEqual(KeyboardModifiers.fromUsage(0xE0), .leftControl)
        XCTAssertEqual(KeyboardModifiers.fromUsage(0xE7), .rightGUI)
        XCTAssertNil(KeyboardModifiers.fromUsage(0x04))
    }
}
