import XCTest
@testable import HIDCore

final class CapsLockMappingTests: XCTestCase {
    func testGlobeHoldsFnWhileCapsLockIsDown() {
        var state = KeyboardState()
        let down = CapsLockMapping.globe.reports(isDown: true, state: &state)
        XCTAssertEqual(down.map(\.fn), [true])
        XCTAssertEqual(down.first?.keys, [])
        let up = CapsLockMapping.globe.reports(isDown: false, state: &state)
        XCTAssertEqual(up.map(\.fn), [false])
    }

    func testControlSpaceTapsTheShortcutOnKeyDownOnly() {
        var state = KeyboardState()
        let down = CapsLockMapping.controlSpace.reports(isDown: true, state: &state)
        XCTAssertEqual(down, [
            KeyboardReport(modifiers: [.leftControl], keys: [0x2C]),
            KeyboardReport(),
        ])
        XCTAssertEqual(CapsLockMapping.controlSpace.reports(isDown: false, state: &state), [])
    }

    func testControlSpaceKeepsModifiersTheUserIsHolding() {
        var state = KeyboardState()
        state.modifiers = [.leftShift]
        let down = CapsLockMapping.controlSpace.reports(isDown: true, state: &state)
        XCTAssertEqual(down.last, KeyboardReport(modifiers: [.leftShift]))
    }

    func testCapsLockPassesTheRealKey() {
        var state = KeyboardState()
        XCTAssertEqual(CapsLockMapping.capsLock.reports(isDown: true, state: &state), [KeyboardReport(keys: [0x39])])
        XCTAssertEqual(CapsLockMapping.capsLock.reports(isDown: false, state: &state), [KeyboardReport()])
    }

    func testDefaultIsGlobeAndRawValuesRoundTrip() {
        XCTAssertEqual(CapsLockMapping.defaultMapping, .globe)
        for mapping in CapsLockMapping.allCases {
            XCTAssertEqual(CapsLockMapping(rawValue: mapping.rawValue), mapping)
        }
    }
}

final class CapsLockMappingSafetyTests: XCTestCase {
    func testReleaseCleansUpEvenIfTheMappingChangedWhileHeld() {
        var state = KeyboardState()
        _ = CapsLockMapping.globe.reports(isDown: true, state: &state)
        let up = CapsLockMapping.controlSpace.reports(isDown: false, state: &state)
        XCTAssertEqual(up, [KeyboardReport()])

        _ = CapsLockMapping.capsLock.reports(isDown: true, state: &state)
        XCTAssertEqual(CapsLockMapping.globe.reports(isDown: false, state: &state), [KeyboardReport()])
    }

    func testRealFnKeyAndCapsLockHoldFnIndependently() {
        var state = KeyboardState()
        _ = CapsLockMapping.globe.reports(isDown: true, state: &state)
        state.setFn(held: true, by: .fnKey)
        state.setFn(held: false, by: .fnKey)
        XCTAssertTrue(state.report.fn, "Caps Lock still holds 🌐")
        _ = CapsLockMapping.globe.reports(isDown: false, state: &state)
        XCTAssertFalse(state.report.fn)
    }

    func testAllUpClearsEveryFnHolder() {
        var state = KeyboardState()
        state.setFn(held: true, by: .fnKey)
        state.setFn(held: true, by: .capsLock)
        state.allUp()
        XCTAssertFalse(state.report.fn)
    }
}
