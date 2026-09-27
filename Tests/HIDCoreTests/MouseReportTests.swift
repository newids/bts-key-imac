import XCTest
@testable import HIDCore

final class MouseReportTests: XCTestCase {
    func testEncodesButtonsAndInt16DeltasLittleEndian() {
        let report = MouseReport(buttons: [.left, .right], dx: 300, dy: -2, wheel: 1, pan: -1)
        XCTAssertEqual(report.bytes, [0x03, 0x2C, 0x01, 0xFE, 0xFF, 0x01, 0xFF])
    }

    func testEmptyReportIsSevenZeroBytes() {
        XCTAssertEqual(MouseReport().bytes, [UInt8](repeating: 0, count: 7))
    }

    func testAccumulatorSumsDeltasUntilDrained() {
        var acc = MouseAccumulator()
        acc.addMovement(dx: 1.5, dy: -0.5)
        acc.addMovement(dx: 1.5, dy: -0.5)
        XCTAssertTrue(acc.hasPendingMovement)
        let report = acc.drain()
        XCTAssertEqual(report.dx, 3)
        XCTAssertEqual(report.dy, -1)
        XCTAssertFalse(acc.hasPendingMovement)
        XCTAssertEqual(acc.drain(), MouseReport())
    }

    func testAccumulatorCarriesFractionalRemainder() {
        var acc = MouseAccumulator()
        acc.addMovement(dx: 0.4, dy: 0)
        XCTAssertEqual(acc.drain().dx, 0)
        acc.addMovement(dx: 0.4, dy: 0)
        XCTAssertEqual(acc.drain().dx, 0)
        acc.addMovement(dx: 0.4, dy: 0)
        XCTAssertEqual(acc.drain().dx, 1)
    }

    func testAccumulatorClampsToInt16() {
        var acc = MouseAccumulator()
        acc.addMovement(dx: 100_000, dy: -100_000)
        let report = acc.drain()
        XCTAssertEqual(report.dx, Int16.max)
        XCTAssertEqual(report.dy, -Int16.max)
    }

    func testAccumulatorKeepsButtonStateAcrossDrains() {
        var acc = MouseAccumulator()
        acc.setButton(.left, pressed: true)
        XCTAssertEqual(acc.drain().buttons, [.left])
        XCTAssertEqual(acc.drain().buttons, [.left])
        acc.setButton(.left, pressed: false)
        XCTAssertEqual(acc.drain().buttons, [])
    }

    func testScrollAccumulatesAndClampsToInt8() {
        var acc = MouseAccumulator()
        acc.addScroll(wheel: 0.6, pan: -500)
        acc.addScroll(wheel: 0.6, pan: 0)
        let report = acc.drain()
        XCTAssertEqual(report.wheel, 1)
        XCTAssertEqual(report.pan, -127)
    }
}
