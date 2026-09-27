import XCTest
@testable import HIDCore

final class PointerScalerTests: XCTestCase {
    func testMultiplierScalesDeltas() {
        let scaler = PointerScaler(multiplier: 2.0)
        let out = scaler.scale(dx: 3, dy: -4)
        XCTAssertEqual(out.dx, 6)
        XCTAssertEqual(out.dy, -8)
    }

    func testMultiplierIsClampedToSupportedRange() {
        XCTAssertEqual(PointerScaler(multiplier: 0.1).multiplier, PointerScaler.minimumMultiplier)
        XCTAssertEqual(PointerScaler(multiplier: 99).multiplier, PointerScaler.maximumMultiplier)
    }
}
