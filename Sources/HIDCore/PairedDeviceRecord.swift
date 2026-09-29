import Foundation

/// One paired device as reported by the helper process that reads the pairing list.
///
/// The list is read out of process: calling `IOBluetoothDevice.pairedDevices()` once makes every
/// later channel open in the same process fail (it returns a Mac paired over both transports as
/// two device objects), so the app itself must never call it.
public struct PairedDeviceRecord: Equatable, Codable, Sendable {
    public let address: String
    public let name: String?
    public let classOfDevice: UInt32

    public init(address: String, name: String?, classOfDevice: UInt32) {
        self.address = address
        self.name = name
        self.classOfDevice = classOfDevice
    }

    public var kind: BluetoothDeviceKind { BluetoothDeviceKind(classOfDevice: classOfDevice) }

    public static func encodeList(_ records: [PairedDeviceRecord]) throws -> Data {
        try JSONEncoder().encode(records)
    }

    /// Decodes and validates the helper's output: addresses are normalized, entries without a
    /// valid address are dropped, and duplicates are merged in favour of the one that knows more.
    public static func decodeList(_ data: Data) throws -> [PairedDeviceRecord] {
        let raw = try JSONDecoder().decode([PairedDeviceRecord].self, from: data)
        var order: [String] = []
        var merged: [String: PairedDeviceRecord] = [:]
        for record in raw {
            let address = InboundPolicy.normalize(record.address)
            guard isValidAddress(address) else { continue }
            let candidate = PairedDeviceRecord(address: address, name: record.name, classOfDevice: record.classOfDevice)
            guard let existing = merged[address] else {
                order.append(address)
                merged[address] = candidate
                continue
            }
            merged[address] = PairedDeviceRecord(
                address: address,
                name: existing.name?.isEmpty == false ? existing.name : candidate.name,
                classOfDevice: existing.classOfDevice != 0 ? existing.classOfDevice : candidate.classOfDevice
            )
        }
        return order.compactMap { merged[$0] }
    }

    private static let octetCount = 6

    private static func isValidAddress(_ address: String) -> Bool {
        let octets = address.split(separator: "-", omittingEmptySubsequences: false)
        return octets.count == octetCount && octets.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isHexDigit) }
    }
}
