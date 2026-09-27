/// Re-enters remote mode automatically when a link that dropped while the user was typing on
/// the iMac comes back soon after, e.g. the iMac slept and now wants its login password.
public struct RemoteResumePolicy: Sendable {
    public let window: Double
    private var droppedAt: Double?

    public init(window: Double = 30 * 60) {
        self.window = window
    }

    public mutating func linkDropped(wasCapturing: Bool, at time: Double) {
        droppedAt = wasCapturing ? time : nil
    }

    /// True once per drop, and only while the window has not elapsed.
    public mutating func shouldResume(at time: Double) -> Bool {
        defer { droppedAt = nil }
        guard let droppedAt else { return false }
        return time - droppedAt <= window
    }

    public mutating func clear() {
        droppedAt = nil
    }
}
