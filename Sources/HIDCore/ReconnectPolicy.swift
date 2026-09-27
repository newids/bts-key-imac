/// Exponential backoff for automatic reconnection, with a cap on unattended attempts.
///
/// A fixed short interval made every retry page the host and bring up a fresh
/// ACL link that the host then dropped as idle, so the link flapped constantly.
/// Endless retries against a host that keeps refusing also kept the app busy in
/// IOBluetooth, so after `maximumAttempts` the app waits for the host or the user.
public struct ReconnectPolicy: Sendable {
    public let initialDelay: Double
    public let maximumDelay: Double
    public let maximumAttempts: Int
    public private(set) var attempt = 0

    public init(initialDelay: Double = 2, maximumDelay: Double = 30, maximumAttempts: Int = 5) {
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.maximumAttempts = maximumAttempts
    }

    /// What the app uses without the user asking: 4 s, 8 s, 10 s, then it stops and waits
    /// for the host or an explicit "connect now". A host that refuses three times in a row
    /// is asleep, unpaired, or busy with another keyboard; paging it further only costs battery.
    public static let unattended = ReconnectPolicy(initialDelay: 4, maximumDelay: 10, maximumAttempts: 3)

    public var isExhausted: Bool { attempt >= maximumAttempts }

    /// Delay in seconds before the next attempt; each call counts as one attempt.
    public mutating func nextDelay() -> Double {
        let delay = min(initialDelay * Double(1 << min(attempt, 16)), maximumDelay)
        attempt += 1
        return delay
    }

    /// Like `nextDelay()`, but nil once the unattended-attempt budget is spent.
    public mutating func nextDelayIfAllowed() -> Double? {
        guard !isExhausted else { return nil }
        return nextDelay()
    }

    public mutating func reset() {
        attempt = 0
    }
}
