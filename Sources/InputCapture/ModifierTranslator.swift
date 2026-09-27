import CoreGraphics
import HIDCore

/// Translates CGEvent flags into HID modifier bits, keeping left/right apart
/// (the right Command key is the Korean/English toggle on Korean keyboards).
enum ModifierTranslator {
    // NX_DEVICE*KEYMASK bits carried in CGEventFlags.rawValue.
    private static let leftControl: UInt64 = 0x0000_0001
    private static let leftShift: UInt64 = 0x0000_0002
    private static let rightShift: UInt64 = 0x0000_0004
    private static let leftCommand: UInt64 = 0x0000_0008
    private static let rightCommand: UInt64 = 0x0000_0010
    private static let leftOption: UInt64 = 0x0000_0020
    private static let rightOption: UInt64 = 0x0000_0040
    private static let rightControl: UInt64 = 0x0000_2000

    static func modifiers(from flags: CGEventFlags) -> KeyboardModifiers {
        let raw = flags.rawValue
        var result: KeyboardModifiers = []
        if raw & leftControl != 0 { result.insert(.leftControl) }
        if raw & rightControl != 0 { result.insert(.rightControl) }
        if raw & leftShift != 0 { result.insert(.leftShift) }
        if raw & rightShift != 0 { result.insert(.rightShift) }
        if raw & leftOption != 0 { result.insert(.leftAlt) }
        if raw & rightOption != 0 { result.insert(.rightAlt) }
        if raw & leftCommand != 0 { result.insert(.leftGUI) }
        if raw & rightCommand != 0 { result.insert(.rightGUI) }

        // Fall back to the generic masks when device-specific bits are absent (e.g. synthetic events).
        if result.isDisjoint(with: [.leftControl, .rightControl]), flags.contains(.maskControl) { result.insert(.leftControl) }
        if result.isDisjoint(with: [.leftShift, .rightShift]), flags.contains(.maskShift) { result.insert(.leftShift) }
        if result.isDisjoint(with: [.leftAlt, .rightAlt]), flags.contains(.maskAlternate) { result.insert(.leftAlt) }
        if result.isDisjoint(with: [.leftGUI, .rightGUI]), flags.contains(.maskCommand) { result.insert(.leftGUI) }
        return result
    }
}
