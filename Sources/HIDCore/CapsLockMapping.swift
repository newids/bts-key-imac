/// What the MacBook's Caps Lock key becomes on the host.
///
/// Measured on an iMac running macOS 15.7.4 (2026-09-29; see `docs/input-source-switching.md`):
/// the host treats this keyboard as a generic Bluetooth keyboard, so it drops the Apple Fn
/// byte, and what switches 한/영 is the host's own modifier remap for this keyboard
/// (Modifier Keys → select this Mac → Caps Lock → 🌐 fn). That remap needs Caps Lock to
/// arrive as Caps Lock, which is why passing it through is the default.
public enum CapsLockMapping: String, CaseIterable, Sendable {
    /// Send Caps Lock itself and let the host's modifier remap turn it into 🌐.
    case capsLock
    /// Hold the Fn/🌐 key, sent as the Apple vendor Fn byte. Only hosts that mark this keyboard
    /// as an Apple one honour it; the app has no say in that.
    case globe
    /// Tap ⌃Space, the "Select the previous input source" shortcut, where the host still has it.
    case controlSpace

    public static let defaultMapping = CapsLockMapping.capsLock

    private static let capsLockUsage: UInt8 = 0x39
    private static let spaceUsage: UInt8 = 0x2C

    /// Reports to send for a physical Caps Lock edge, updating `state` accordingly.
    public func reports(isDown: Bool, state: inout KeyboardState) -> [KeyboardReport] {
        guard isDown else { return Self.release(state: &state) }
        switch self {
        case .globe:
            state.setFn(held: true, by: .capsLock)
            return [state.report]
        case .capsLock:
            state.press(Self.capsLockUsage)
            return [state.report]
        case .controlSpace:
            var chord = state
            chord.modifiers.insert(.leftControl)
            chord.press(Self.spaceUsage)
            return [chord.report, state.report]
        }
    }

    /// Undoes whatever any mapping did on key-down, so changing the mapping while the key
    /// is held can never leave 🌐 or Caps Lock stuck on the host.
    private static func release(state: inout KeyboardState) -> [KeyboardReport] {
        let before = state.report
        state.setFn(held: false, by: .capsLock)
        state.release(capsLockUsage)
        return state.report == before ? [] : [state.report]
    }
}
