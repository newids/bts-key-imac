import XCTest
@testable import HIDCore

final class BluetoothDeviceKindTests: XCTestCase {
    // Class of Device: major in bits 8-12, minor in bits 2-7.
    private func cod(major: UInt32, minor: UInt32) -> UInt32 { (major << 8) | (minor << 2) }

    func testComputerMinorsMapToConcreteKinds() {
        XCTAssertEqual(BluetoothDeviceKind(classOfDevice: cod(major: 1, minor: 1)), .desktop)
        XCTAssertEqual(BluetoothDeviceKind(classOfDevice: cod(major: 1, minor: 3)), .laptop)
        XCTAssertEqual(BluetoothDeviceKind(classOfDevice: cod(major: 1, minor: 7)), .tablet)
        XCTAssertEqual(BluetoothDeviceKind(classOfDevice: cod(major: 1, minor: 0)), .computer)
    }

    func testOtherMajorsMapToPhoneKeyboardPointerOrOther() {
        XCTAssertEqual(BluetoothDeviceKind(classOfDevice: cod(major: 2, minor: 3)), .phone)
        XCTAssertEqual(BluetoothDeviceKind(classOfDevice: cod(major: 5, minor: 0x10)), .keyboard)
        XCTAssertEqual(BluetoothDeviceKind(classOfDevice: cod(major: 5, minor: 0x20)), .pointer)
        XCTAssertEqual(BluetoothDeviceKind(classOfDevice: cod(major: 4, minor: 1)), .audio)
        XCTAssertEqual(BluetoothDeviceKind(classOfDevice: cod(major: 31, minor: 0)), .other)
    }

    func testEveryKindHasASymbolAndComputersAreHostCandidates() {
        for kind in BluetoothDeviceKind.allCases {
            XCTAssertFalse(kind.symbolName.isEmpty, "\(kind)")
        }
        XCTAssertTrue(BluetoothDeviceKind.desktop.canHostKeyboard)
        XCTAssertTrue(BluetoothDeviceKind.laptop.canHostKeyboard)
        XCTAssertFalse(BluetoothDeviceKind.keyboard.canHostKeyboard)
        XCTAssertFalse(BluetoothDeviceKind.audio.canHostKeyboard)
    }
}
