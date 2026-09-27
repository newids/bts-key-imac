/// Exponential backoff for automatic reconnection.
///
/// A fixed short interval made every retry page the host and bring up a fresh
/// ACL link that the host then dropped as idle, so the link flapped constantly.
public struct ReconnectPolicy: Sendable {
    public let initialDelay: Double
    public let maximumDelay: Double
    public private(set) var attempt = 0

    public init(initialDelay: Double = 2, maximumDelay: Double = 30) {
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
    }

    /// Delay in seconds before the next attempt; each call counts as one attempt.
    public mutating func nextDelay() -> Double {
        let delay = min(initialDelay * Double(1 << min(attempt, 16)), maximumDelay)
        attempt += 1
        return delay
    }

    public mutating func reset() {
        attempt = 0
    }
}
