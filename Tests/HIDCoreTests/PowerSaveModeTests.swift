import XCTest
@testable import HIDCore

final class PowerSaveModeTests: XCTestCase {
    func testTargetBrightnessPerMode() {
        XCTAssertNil(PowerSaveMode.off.targetBrightness)
        XCTAssertEqual(PowerSaveMode.dim.targetBrightness, 0.1)
        XCTAssertEqual(PowerSaveMode.blank.targetBrightness, 0.0)
    }

    func testNeverRaisesBrightnessThatIsAlreadyLower() {
        XCTAssertEqual(PowerSaveMode.dim.brightness(forCurrent: 0.05), 0.05)
        XCTAssertEqual(PowerSaveMode.dim.brightness(forCurrent: 0.8), 0.1)
        XCTAssertNil(PowerSaveMode.off.brightness(forCurrent: 0.8))
    }

    func testRoundTripsThroughRawValueForSettings() {
        for mode in PowerSaveMode.allCases {
            XCTAssertEqual(PowerSaveMode(rawValue: mode.rawValue), mode)
        }
        XCTAssertEqual(PowerSaveMode.defaultMode, .dim)
    }
}
