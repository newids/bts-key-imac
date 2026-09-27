import XCTest
import HIDCore
@testable import ClassicHIDTransport

final class SDPRecordBuilderTests: XCTestCase {
    private let record = SDPRecordBuilder(serviceName: "Test Keyboard", providerName: "Tester").dictionary

    func testDeclaresHIDServiceClassAndProfile() {
        let classList = record["0001 - ServiceClassIDList"] as? [Data]
        XCTAssertEqual(classList, [Data([0x11, 0x24])])
        let profiles = record["0009 - BluetoothProfileDescriptorList"] as? [[Any]]
        XCTAssertEqual(profiles?.first?.first as? Data, Data([0x11, 0x24]))
    }

    func testControlAndInterruptPSMs() {
        let protocols = record["0004 - ProtocolDescriptorList"] as? [[Any]]
        let l2cap = protocols?.first
        XCTAssertEqual(l2cap?.first as? Data, Data([0x01, 0x00]))
        XCTAssertEqual(SDPRecordBuilder.uint16Value(l2cap?[1]), 0x0011)

        let additional = record["000D - AdditionalProtocolDescriptorLists"] as? [[[Any]]]
        let interrupt = additional?.first?.first
        XCTAssertEqual(SDPRecordBuilder.uint16Value(interrupt?[1]), 0x0013)
    }

    func testHIDAttributesDescribeCompositeReconnectingDevice() {
        XCTAssertEqual(SDPRecordBuilder.uint8Value(record["0202 - HIDDeviceSubclass"]), 0xC0)
        XCTAssertEqual(record["0205 - HIDReconnectInitiate"] as? Bool, true)
        XCTAssertEqual(record["0204 - HIDVirtualCable"] as? Bool, true)
        XCTAssertEqual(record["020D - HIDNormallyConnectable"] as? Bool, true)
        XCTAssertEqual(SDPRecordBuilder.uint16Value(record["0201 - HIDParserVersion"]), 0x0111)
    }

    func testEmbedsTheSharedReportDescriptor() {
        let list = record["0206 - HIDDescriptorList"] as? [[Any]]
        let entry = list?.first
        XCTAssertEqual(SDPRecordBuilder.uint8Value(entry?.first), 0x22)
        let descriptor = entry?[1] as? [String: Any]
        XCTAssertEqual(descriptor?["DataElementValue"] as? Data, Data(ReportDescriptor.bytes))
    }

    func testServiceStringsAreCarried() {
        XCTAssertEqual(record["0100 - ServiceName"] as? String, "Test Keyboard")
        XCTAssertEqual(record["0102 - ProviderName"] as? String, "Tester")
    }
}
