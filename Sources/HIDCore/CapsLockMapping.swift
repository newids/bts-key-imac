/// What the MacBook's Caps Lock key becomes on the iMac.
///
/// Mac hosts remap modifier keys per keyboard, so an iMac set to "Caps Lock → 🌐" does not
/// apply that to a newly seen keyboard. Converting on the MacBook side avoids needing any
/// setting on the (managed) iMac.
public enum CapsLockMapping: String, CaseIterable, Sendable {
    /// Hold the Fn/🌐 key: works with "Press 🌐 to change input source" (Sequoia default).
    case globe
    /// Tap ⌃Space, the "Select the previous input source" shortcut.
    case controlSpace
    /// Send Caps Lock itself.
    case capsLock

    public static let defaultMapping = CapsLockMapping.globe

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
