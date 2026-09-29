/// Bounds how often a host that pages this Mac on its own can make the app connect.
///
/// An iMac that still lists this Mac as its keyboard keeps paging it, and every page used to
/// restart a full round of attempts, so a link that could not come up was retried forever and
/// kept the MacBook's radio busy. One cue is honoured after the last working link or the last
/// explicit request from the user; after that only the user starts a connection.
public struct HostCuePolicy: Sendable {
    public let allowance: Int
    public private(set) var used = 0

    public init(allowance: Int = 1) {
        self.allowance = allowance
    }

    public var isExhausted: Bool { used >= allowance }

    /// True when this cue may start a connection; each true answer spends one cue.
    public mutating func shouldHonorCue() -> Bool {
        guard !isExhausted else { return false }
        used += 1
        return true
    }

    /// A working link or a request from the user proves the situation changed.
    public mutating func reset() {
        used = 0
    }
}
