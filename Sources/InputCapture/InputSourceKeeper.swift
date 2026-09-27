import Carbon
import Foundation

/// Remembers the MacBook's keyboard input source when entering remote mode and restores it
/// afterwards, so 한/영 taps meant for the iMac do not leave the MacBook in the other language.
/// The source ID is persisted so a crash during remote mode is repaired on next launch.
public final class InputSourceKeeper {
    private static let savedKey = "savedInputSourceID"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    public func save() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = Self.identifier(of: source) else { return }
        defaults.set(id, forKey: Self.savedKey)
    }

    public func restore() {
        guard let id = defaults.string(forKey: Self.savedKey) else { return }
        defer { defaults.removeObject(forKey: Self.savedKey) }
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return }
        TISSelectInputSource(source)
    }

    private static func identifier(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
