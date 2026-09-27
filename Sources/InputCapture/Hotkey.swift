import CoreGraphics

/// A modifier chord plus a key that toggles local/remote mode.
public struct Hotkey: Equatable, Sendable {
    public var keyCode: Int
    public var requiresControl: Bool
    public var requiresOption: Bool
    public var requiresCommand: Bool
    public var requiresShift: Bool

    /// ⌥⌘K. Checked on the dev Mac: no system symbolic hotkey or global key equivalent uses it.
    public static let `default` = Hotkey(keyCode: 40, requiresControl: false, requiresOption: true, requiresCommand: true, requiresShift: false)

    public init(keyCode: Int, requiresControl: Bool, requiresOption: Bool, requiresCommand: Bool, requiresShift: Bool) {
        self.keyCode = keyCode
        self.requiresControl = requiresControl
        self.requiresOption = requiresOption
        self.requiresCommand = requiresCommand
        self.requiresShift = requiresShift
    }

    public func matches(keyCode: Int, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode
            && flags.contains(.maskControl) == requiresControl
            && flags.contains(.maskAlternate) == requiresOption
            && flags.contains(.maskCommand) == requiresCommand
            && flags.contains(.maskShift) == requiresShift
    }

    public var displayString: String {
        var parts: [String] = []
        if requiresControl { parts.append("⌃") }
        if requiresOption { parts.append("⌥") }
        if requiresShift { parts.append("⇧") }
        if requiresCommand { parts.append("⌘") }
        parts.append(Self.keyNames[keyCode] ?? "key \(keyCode)")
        return parts.joined()
    }

    private static let keyNames: [Int: String] = [
        40: "K", 0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 45: "N", 46: "M", 49: "Space", 53: "Esc", 50: "`",
    ]
}
