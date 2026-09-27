/// Difference between two snapshots of the paired-computer list.
///
/// The app cannot be told by macOS when the user pairs or forgets an iMac, so it
/// polls the list; a newly paired computer is what the user wants to connect to next,
/// and a forgotten one must stop being retried.
public struct PairingChange: Equatable, Sendable {
    public let added: Set<String>
    public let removed: Set<String>

    /// `before` is nil for the first snapshot, which seeds the watcher without reporting additions.
    public init(before: Set<String>?, after: Set<String>) {
        let normalizedAfter = Set(after.map(InboundPolicy.normalize))
        guard let before else {
            added = []
            removed = []
            return
        }
        let normalizedBefore = Set(before.map(InboundPolicy.normalize))
        // An empty list after a non-empty one means the daemon is restarting or Bluetooth is
        // off, not that the user unpaired everything at once.
        guard !(normalizedAfter.isEmpty && !normalizedBefore.isEmpty) else {
            added = []
            removed = []
            return
        }
        added = normalizedAfter.subtracting(normalizedBefore)
        removed = normalizedBefore.subtracting(normalizedAfter)
    }

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty }
}

/// A pairing only counts as removed when it is missing from two consecutive snapshots,
/// so a single partial list from a busy daemon cannot wipe history or drop the target.
public struct PairingRemovalDebounce: Sendable {
    private var pending: Set<String> = []

    public init() {}

    public mutating func confirmedRemovals(candidates: Set<String>) -> Set<String> {
        let confirmed = candidates.intersection(pending)
        pending = candidates.subtracting(confirmed)
        return confirmed
    }
}
