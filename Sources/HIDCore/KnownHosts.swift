import Foundation

/// A host this Mac has served as a keyboard before.
public struct KnownHost: Equatable, Codable, Sendable {
    public let address: String
    public var name: String
    public var kind: BluetoothDeviceKind
    public var lastConnected: Double

    public init(address: String, name: String, kind: BluetoothDeviceKind, lastConnected: Double) {
        self.address = address
        self.name = name
        self.kind = kind
        self.lastConnected = lastConnected
    }
}

/// Most-recent-first history of hosts, like the device list in the macOS Bluetooth menu.
public struct KnownHosts: Equatable, Sendable {
    public static let defaultLimit = 8

    public private(set) var entries: [KnownHost]
    public let limit: Int

    public init(limit: Int = KnownHosts.defaultLimit) {
        entries = []
        self.limit = limit
    }

    public init(encoded data: Data, limit: Int = KnownHosts.defaultLimit) throws {
        entries = try JSONDecoder().decode([KnownHost].self, from: data)
        self.limit = limit
    }

    public init(encoded data: Data, limit: Int = KnownHosts.defaultLimit, fallbackToEmpty: Bool) {
        self = (try? KnownHosts(encoded: data, limit: limit)) ?? KnownHosts(limit: limit)
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(entries)
    }

    public mutating func record(address: String, name: String, kind: BluetoothDeviceKind, at time: Double) {
        let key = InboundPolicy.normalize(address)
        var rest = entries.filter { $0.address != key }
        rest.append(KnownHost(address: key, name: name, kind: kind, lastConnected: time))
        entries = Array(rest.sorted { $0.lastConnected > $1.lastConnected }.prefix(limit))
    }

    public mutating func forget(address: String) {
        let key = InboundPolicy.normalize(address)
        entries.removeAll { $0.address == key }
    }

    public func contains(address: String) -> Bool {
        entries.contains { $0.address == InboundPolicy.normalize(address) }
    }
}
