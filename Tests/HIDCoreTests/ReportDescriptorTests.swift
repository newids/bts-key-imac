import XCTest
@testable import HIDCore

final class ReportDescriptorTests: XCTestCase {
    func testDescriptorHasBalancedCollections() {
        let bytes = ReportDescriptor.bytes
        var depth = 0
        var i = 0
        while i < bytes.count {
            let prefix = bytes[i]
            let size = [0, 1, 2, 4][Int(prefix & 0x03)]
            if prefix & 0xFC == 0xA0 { depth += 1 }
            if prefix & 0xFC == 0xC0 { depth -= 1 }
            i += 1 + size
        }
        XCTAssertEqual(depth, 0)
        XCTAssertEqual(i, bytes.count, "descriptor must decode to an exact item boundary")
    }

    func testDescriptorDeclaresBothReportIDs() {
        let bytes = ReportDescriptor.bytes
        XCTAssertTrue(bytes.contains(subsequence: [0x85, HIDReportID.keyboard.rawValue]))
        XCTAssertTrue(bytes.contains(subsequence: [0x85, HIDReportID.mouse.rawValue]))
    }

    func testKeyboardDeclaresAppleVendorFnByte() {
        // Usage Page 0xFF (Apple vendor top case), Usage 0x03 (Keyboard Fn), 8 bits x 1, Input.
        XCTAssertTrue(ReportDescriptor.bytes.contains(subsequence: [0x05, 0xFF, 0x09, 0x03, 0x15, 0x00, 0x25, 0x01, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02]))
    }

    func testMouseAxesAreSixteenBit() {
        // Logical min -32767 (0x8001), max 32767 (0x7FFF), report size 16.
        XCTAssertTrue(ReportDescriptor.bytes.contains(subsequence: [0x16, 0x01, 0x80, 0x26, 0xFF, 0x7F, 0x75, 0x10]))
    }
}

private extension Array where Element: Equatable {
    func contains(subsequence: [Element]) -> Bool {
        guard !subsequence.isEmpty, count >= subsequence.count else { return false }
        return (0...(count - subsequence.count)).contains { self[$0..<($0 + subsequence.count)].elementsEqual(subsequence) }
    }
}
