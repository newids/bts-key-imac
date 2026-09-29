import XCTest
@testable import HIDCore

final class CapsLockPreferencesTests: XCTestCase {
    private let imacA = "aa-aa-aa-aa-aa-01"
    private let imacB = "bb-bb-bb-bb-bb-02"

    func testAHostWithoutItsOwnChoiceUsesTheGeneralOne() {
        let preferences = CapsLockPreferences(general: .controlSpace)
        XCTAssertEqual(preferences.mapping(for: imacA), .controlSpace)
        XCTAssertEqual(preferences.mapping(for: nil), .controlSpace)
    }

    func testEachHostKeepsItsOwnChoice() {
        var preferences = CapsLockPreferences()
        preferences.set(.capsLock, for: imacA)
        preferences.set(.controlSpace, for: "BB:BB:BB:BB:BB:02")
        XCTAssertEqual(preferences.mapping(for: "AA:AA:AA:AA:AA:01"), .capsLock)
        XCTAssertEqual(preferences.mapping(for: imacB), .controlSpace)
        XCTAssertEqual(preferences.mapping(for: "cc-cc-cc-cc-cc-03"), CapsLockMapping.defaultMapping)
    }

    func testChoosingWithoutAHostChangesTheGeneralChoice() {
        var preferences = CapsLockPreferences()
        preferences.set(.globe, for: nil)
        XCTAssertEqual(preferences.general, .globe)
        XCTAssertEqual(preferences.mapping(for: imacA), .globe)
    }

    func testForgettingAHostDropsItsChoice() {
        var preferences = CapsLockPreferences()
        preferences.set(.globe, for: imacA)
        preferences.forget(imacA)
        XCTAssertFalse(preferences.hasOwnChoice(imacA))
        XCTAssertEqual(preferences.mapping(for: imacA), CapsLockMapping.defaultMapping)
    }

    func testRoundTripsThroughJSONAndSurvivesUnknownValues() throws {
        var preferences = CapsLockPreferences(general: .controlSpace)
        preferences.set(.capsLock, for: imacA)
        let decoded = try JSONDecoder().decode(CapsLockPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded, preferences)

        // A choice written by a newer version must not take the other hosts' choices down with it.
        let newer = Data(#"{"general":"controlSpace","hosts":{"aa-aa-aa-aa-aa-01":"somethingNew","bb-bb-bb-bb-bb-02":"capsLock"}}"#.utf8)
        let tolerant = try JSONDecoder().decode(CapsLockPreferences.self, from: newer)
        XCTAssertEqual(tolerant.mapping(for: imacA), .controlSpace)
        XCTAssertEqual(tolerant.mapping(for: imacB), .capsLock)
    }
}
