/// Which key Caps Lock becomes, per host.
///
/// What switches the input source depends on the host's own settings (its 🌐 key action, its
/// shortcuts, whether it treats this keyboard as an Apple one), and the user moves between
/// hosts that are set up differently, so one choice for all of them cannot be right.
public struct CapsLockPreferences: Equatable, Sendable {
    /// Used for hosts without a choice of their own.
    public private(set) var general: CapsLockMapping
    private var hosts: [String: CapsLockMapping]

    public init(general: CapsLockMapping = .defaultMapping) {
        self.general = general
        hosts = [:]
    }

    public func mapping(for address: String?) -> CapsLockMapping {
        guard let address else { return general }
        return hosts[InboundPolicy.normalize(address)] ?? general
    }

    public func hasOwnChoice(_ address: String) -> Bool {
        hosts[InboundPolicy.normalize(address)] != nil
    }

    /// Records the choice for `address`, or as the general choice when there is no host.
    public mutating func set(_ mapping: CapsLockMapping, for address: String?) {
        guard let address else {
            general = mapping
            return
        }
        hosts[InboundPolicy.normalize(address)] = mapping
    }

    public mutating func forget(_ address: String) {
        hosts[InboundPolicy.normalize(address)] = nil
    }
}

extension CapsLockPreferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case general, hosts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedGeneral = try container.decodeIfPresent(String.self, forKey: .general)
        general = storedGeneral.flatMap(CapsLockMapping.init(rawValue:)) ?? .defaultMapping
        let stored = try container.decodeIfPresent([String: String].self, forKey: .hosts) ?? [:]
        // Values this version does not know are dropped one by one, not the whole table.
        hosts = stored.reduce(into: [:]) { result, entry in
            guard let mapping = CapsLockMapping(rawValue: entry.value) else { return }
            result[InboundPolicy.normalize(entry.key)] = mapping
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(general.rawValue, forKey: .general)
        try container.encode(hosts.mapValues(\.rawValue), forKey: .hosts)
    }
}
