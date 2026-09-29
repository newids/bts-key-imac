import XCTest
@testable import HIDCore

final class PairedDeviceRecordTests: XCTestCase {
    func testRoundTripsThroughTheHelperOutputFormat() throws {
        let records = [
            PairedDeviceRecord(address: "AA:AA:AA:AA:AA:01", name: "iMac-A", classOfDevice: 0),
            PairedDeviceRecord(address: "bb-bb-bb-bb-bb-02", name: "iMac-B", classOfDevice: 0x3a0104),
        ]
        let decoded = try PairedDeviceRecord.decodeList(PairedDeviceRecord.encodeList(records))
        XCTAssertEqual(decoded.map(\.address), ["aa-aa-aa-aa-aa-01", "bb-bb-bb-bb-bb-02"], "addresses are normalized")
        XCTAssertEqual(decoded.map(\.kind), [.unknown, .desktop])
        XCTAssertEqual(decoded.first?.name, "iMac-A")
    }

    func testDuplicateAddressesCollapseIntoOneRecord() throws {
        // bluetoothd lists a Mac paired over both transports twice.
        let twice = [
            PairedDeviceRecord(address: "aa-aa-aa-aa-aa-01", name: nil, classOfDevice: 0),
            PairedDeviceRecord(address: "AA:AA:AA:AA:AA:01", name: "iMac-A", classOfDevice: 0x3a0104),
        ]
        let decoded = try PairedDeviceRecord.decodeList(PairedDeviceRecord.encodeList(twice))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.name, "iMac-A", "the entry that knows more wins")
        XCTAssertEqual(decoded.first?.kind, .desktop)
    }

    func testRejectsOutputThatIsNotAListOfDevices() {
        XCTAssertThrowsError(try PairedDeviceRecord.decodeList(Data("not json".utf8)))
        XCTAssertThrowsError(try PairedDeviceRecord.decodeList(Data(#"{"address":"x"}"#.utf8)))
    }

    func testDropsEntriesWithoutAValidAddress() throws {
        let data = Data(#"[{"address":"zz","name":"junk","classOfDevice":0},{"address":"cc-cc-cc-cc-cc-03","name":"PC-A","classOfDevice":3801348}]"#.utf8)
        XCTAssertEqual(try PairedDeviceRecord.decodeList(data).map(\.name), ["PC-A"])
    }

    func testAnEmptyListIsValid() throws {
        XCTAssertTrue(try PairedDeviceRecord.decodeList(Data("[]".utf8)).isEmpty)
    }
}
