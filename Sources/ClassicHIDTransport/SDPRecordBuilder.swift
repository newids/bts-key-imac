import Foundation
import HIDCore

/// Builds the IOBluetooth SDP dictionary that advertises this Mac as a
/// Bluetooth Classic HID keyboard + pointing device (service class 0x1124).
///
/// Dictionary format follows IOBluetoothSDPServiceRecord's
/// `publishedServiceRecord(with:)` conventions: keys are "XXXX - Name",
/// raw `Data` elements are UUIDs, `Bool` are booleans, and explicit
/// `DataElementType`/`DataElementValue` dictionaries encode integers/strings.
public struct SDPRecordBuilder {
    public static let hidServiceClass = Data([0x11, 0x24])
    public static let l2capProtocol = Data([0x01, 0x00])
    public static let hidProtocol = Data([0x00, 0x11])
    public static let publicBrowseGroup = Data([0x10, 0x02])
    public static let controlPSM: UInt16 = 0x0011
    public static let interruptPSM: UInt16 = 0x0013

    private static let deviceSubclassKeyboardAndPointing: UInt8 = 0xC0
    private static let countryCodeUS: UInt8 = 0x21
    private static let classDescriptorTypeReport: UInt8 = 0x22
    private static let hidParserVersion: UInt16 = 0x0111
    private static let hidProfileVersion: UInt16 = 0x0100
    private static let supervisionTimeout: UInt16 = 0x1F40
    private static let languageEnglishUS: UInt16 = 0x0409

    private enum ElementType: Int {
        case unsignedInt = 1
        case string = 4
    }

    public let serviceName: String
    public let providerName: String

    public init(serviceName: String, providerName: String) {
        self.serviceName = serviceName
        self.providerName = providerName
    }

    public var dictionary: [String: Any] {
        [
            "0001 - ServiceClassIDList": [Self.hidServiceClass],
            "0004 - ProtocolDescriptorList": [
                [Self.l2capProtocol, Self.uint16(Self.controlPSM)],
                [Self.hidProtocol],
            ],
            "0005 - BrowseGroupList": [Self.publicBrowseGroup],
            "0006 - LanguageBaseAttributeIDList": [Self.uint16(0x656E), Self.uint16(0x006A), Self.uint16(0x0100)],
            "0009 - BluetoothProfileDescriptorList": [[Self.hidServiceClass, Self.uint16(0x0101)]],
            "000D - AdditionalProtocolDescriptorLists": [[
                [Self.l2capProtocol, Self.uint16(Self.interruptPSM)],
                [Self.hidProtocol],
            ]],
            "0100 - ServiceName": serviceName,
            "0101 - ServiceDescription": "Keyboard and Mouse",
            "0102 - ProviderName": providerName,
            "0201 - HIDParserVersion": Self.uint16(Self.hidParserVersion),
            "0202 - HIDDeviceSubclass": Self.uint8(Self.deviceSubclassKeyboardAndPointing),
            "0203 - HIDCountryCode": Self.uint8(Self.countryCodeUS),
            "0204 - HIDVirtualCable": true,
            "0205 - HIDReconnectInitiate": true,
            "0206 - HIDDescriptorList": [[
                Self.uint8(Self.classDescriptorTypeReport),
                Self.string(Data(ReportDescriptor.bytes)),
            ]],
            "0207 - HIDLANGIDBaseList": [[Self.uint16(Self.languageEnglishUS), Self.uint16(0x0100)]],
            "0209 - HIDBatteryPower": true,
            "020A - HIDRemoteWake": true,
            "020B - HIDProfileVersion": Self.uint16(Self.hidProfileVersion),
            "020C - HIDSupervisionTimeout": Self.uint16(Self.supervisionTimeout),
            "020D - HIDNormallyConnectable": true,
            "020E - HIDBootDevice": true,
        ]
    }

    // MARK: - Element helpers

    private static func uint8(_ value: UInt8) -> [String: Any] {
        element(.unsignedInt, Data([value]))
    }

    private static func uint16(_ value: UInt16) -> [String: Any] {
        element(.unsignedInt, Data([UInt8(value >> 8), UInt8(value & 0xFF)]))
    }

    private static func string(_ data: Data) -> [String: Any] {
        element(.string, data)
    }

    private static func element(_ type: ElementType, _ data: Data) -> [String: Any] {
        ["DataElementType": type.rawValue, "DataElementSize": 0, "DataElementValue": data]
    }

    // MARK: - Test helpers (decode what the builder produced)

    static func uint16Value(_ element: Any?) -> UInt16? {
        guard let data = (element as? [String: Any])?["DataElementValue"] as? Data, data.count == 2 else { return nil }
        return UInt16(data[data.startIndex]) << 8 | UInt16(data[data.startIndex + 1])
    }

    static func uint8Value(_ element: Any?) -> UInt8? {
        guard let data = (element as? [String: Any])?["DataElementValue"] as? Data, data.count == 1 else { return nil }
        return data[data.startIndex]
    }
}
