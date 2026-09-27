import XCTest
@testable import HIDCore

final class HIDPFrameTests: XCTestCase {
    func testDataInputFrameHasHeaderAndReportID() {
        let frame = HIDPFrame.dataInput(reportID: .keyboard, payload: [1, 2, 3])
        XCTAssertEqual(frame, [0xA1, 0x01, 1, 2, 3])
    }

    func testParsesSetProtocolAndVirtualCableUnplug() {
        XCTAssertEqual(HIDPFrame.parse([0x71]), .setProtocol(.report))
        XCTAssertEqual(HIDPFrame.parse([0x70]), .setProtocol(.boot))
        XCTAssertEqual(HIDPFrame.parse([0x15]), .virtualCableUnplug)
    }

    func testParsesGetAndSetReport() {
        XCTAssertEqual(HIDPFrame.parse([0x41, 0x01]), .getReport(type: .input, reportID: 0x01))
        XCTAssertEqual(HIDPFrame.parse([0x52, 0x01, 0x02]), .setReport(type: .output, payload: [0x01, 0x02]))
    }

    func testUnknownAndEmptyFramesAreReportedAsUnknown() {
        XCTAssertEqual(HIDPFrame.parse([]), .unknown)
        XCTAssertEqual(HIDPFrame.parse([0xF0]), .unknown)
    }

    func testHandshakeEncoding() {
        XCTAssertEqual(HIDPFrame.handshake(.successful), [0x00])
        XCTAssertEqual(HIDPFrame.handshake(.unsupportedRequest), [0x03])
    }
}
