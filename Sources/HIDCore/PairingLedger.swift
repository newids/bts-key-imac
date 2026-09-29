/// What the app remembers about Bluetooth pairings across launches.
///
/// macOS does not say when a pairing was made, so the app records when it first saw each one.
/// Keeping the record on disk lets a pairing made while the app was not running count as new
/// at the next launch, instead of being absorbed into the first snapshot.
public struct PairingLedger: Equatable, Codable, Sendable {
    /// Time of first sighting for pairings that already existed when tracking began.
    public static let unknownAge: Double = 0

    private var firstSeen: [String: Double] = [:]
    public private(set) var isSeeded = false
    /// Missing from the last list only; a second miss confirms the removal.
    private var missingOnce: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case firstSeen, isSeeded
    }

    public init() {}

    /// Compares what is stored; the removal debounce is transient.
    public static func == (lhs: PairingLedger, rhs: PairingLedger) -> Bool {
        lhs.firstSeen == rhs.firstSeen && lhs.isSeeded == rhs.isSeeded
    }

    /// When the pairing with `address` was first seen, `unknownAge` if it predates tracking,
    /// nil if the address is not paired.
    public func pairedSince(_ address: String) -> Double? {
        firstSeen[InboundPolicy.normalize(address)]
    }

    /// Folds the current list of paired computers into the ledger and reports what changed.
    public mutating func observe(paired: Set<String>, at time: Double) -> PairingChange {
        let current = Set(paired.map(InboundPolicy.normalize))
        // An empty list means the daemon is restarting or Bluetooth is off.
        guard !current.isEmpty else { return PairingChange(added: [], removed: []) }
        guard isSeeded else {
            firstSeen = Dictionary(uniqueKeysWithValues: current.map { ($0, Self.unknownAge) })
            isSeeded = true
            return PairingChange(added: [], removed: [])
        }
        let added = current.subtracting(firstSeen.keys)
        let missing = Set(firstSeen.keys).subtracting(current)
        let removed = missing.intersection(missingOnce)
        missingOnce = missing.subtracting(removed)
        firstSeen = firstSeen
            .filter { !removed.contains($0.key) }
            .merging(added.map { ($0, time) }) { existing, _ in existing }
        return PairingChange(added: added, removed: removed)
    }
}

/// How well this Mac knows a host, which decides the connection flow and what the menu says.
public enum HostFamiliarity: Equatable, Sendable {
    /// Paired while the app was tracking and never served: the iMac the user just moved to.
    case new
    /// Served before under the current pairing.
    case returning
    /// Served before, then paired again; the host starts over with a fresh link key.
    case repaired
    /// Paired before tracking began and never served.
    case untried
    case unpaired

    public init(isPaired: Bool, pairedSince: Double?, lastServed: Double?) {
        guard isPaired else {
            self = .unpaired
            return
        }
        let since = pairedSince ?? PairingLedger.unknownAge
        guard let lastServed, lastServed > 0 else {
            self = since > PairingLedger.unknownAge ? .new : .untried
            return
        }
        self = since > lastServed ? .repaired : .returning
    }

    /// True when the host has never exchanged HID traffic under its current pairing.
    public var isFirstConnection: Bool {
        switch self {
        case .new, .repaired, .untried: return true
        case .returning, .unpaired: return false
        }
    }
}
