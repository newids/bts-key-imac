import AppKit
import CoreGraphics

/// Freezes and hides the MacBook pointer while input goes to the iMac.
///
/// A background (menu bar) app cannot rely on `CGAssociateMouseAndMouseCursorPosition`
/// or `NSCursor.hide()`, which only take effect for the active app; the pointer kept
/// moving on the MacBook. The pointer is therefore warped back to its anchor after
/// every motion event (motion deltas are read from the event, so they are unaffected),
/// and hidden with the window server's background-cursor property, as KVM tools do.
public final class CursorLock {
    private var anchor: CGPoint?
    private var isHidden = false
    private var lastPin = Date.distantPast
    /// Warping on every motion event adds a window-server round trip to the event tap's hot path.
    private static let minimumPinInterval: TimeInterval = 1.0 / 60

    public init() {}

    public var isLocked: Bool { anchor != nil }

    public func lock() {
        guard anchor == nil else { return }
        anchor = CGEvent(source: nil)?.location
        // Warps normally suppress local input for 0.25 s; the pointer must keep reporting deltas.
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        CGAssociateMouseAndMouseCursorPosition(0)
        hideCursor()
    }

    /// Call from the event tap for every motion event while locked.
    public func pin() {
        guard let anchor else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPin) >= Self.minimumPinInterval else { return }
        lastPin = now
        CGWarpMouseCursorPosition(anchor)
    }

    public func unlock() {
        guard let anchor else { return }
        self.anchor = nil
        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(anchor)
        showCursor()
    }

    private func hideCursor() {
        guard !isHidden else { return }
        BackgroundCursor.allow()
        CGDisplayHideCursor(CGMainDisplayID())
        NSCursor.hide()
        isHidden = true
    }

    private func showCursor() {
        guard isHidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        NSCursor.unhide()
        isHidden = false
    }
}

/// Lets a background app hide the cursor (window-server connection property, resolved at runtime).
private enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private static var didAllow = false

    static func allow() {
        guard !didAllow,
              let connectionSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_CGSDefaultConnection"),
              let setSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(setSymbol, to: SetProperty.self)
        _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        didAllow = true
    }
}
