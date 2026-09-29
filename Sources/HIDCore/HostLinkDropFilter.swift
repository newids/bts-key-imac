/// Tells a link the host brought up from the app's own, by their disconnect notifications.
///
/// macOS shows this process nothing of a link the host opens: no connect notification, no
/// channel notification, and `isConnected()` stays false (measured 2026-09-29). The only sign
/// is the disconnect notification when that link goes down, 16 to 19 s after the host's attempt.
/// The same notification also fires for links this app opened and released, which must not
/// count as the host asking for its keyboard.
public struct HostLinkDropFilter: Sendable {
    /// How long after releasing its own link the app attributes a drop to that link.
    public static let window: Double = 20

    private var ownDropExpectedUntil: Double?

    public init() {}

    /// Call when the app lets go of a link it used.
    public mutating func expectOwnDrop(at now: Double) {
        ownDropExpectedUntil = now + Self.window
    }

    /// Whether the link that dropped at `now` was the host's. Consumes the expectation.
    public mutating func isHostLinkDrop(at now: Double) -> Bool {
        defer { ownDropExpectedUntil = nil }
        guard let until = ownDropExpectedUntil else { return true }
        return now > until
    }
}
