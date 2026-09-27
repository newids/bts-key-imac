import Foundation
import HIDCore
import InputCapture

/// User preferences backed by UserDefaults.
struct Settings {
    private enum Key {
        static let targetAddress = "targetAddress"
        static let targetName = "targetName"
        static let pointerMultiplier = "pointerMultiplier"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let wantsConnection = "wantsConnection"
        static let isPaused = "isPaused"
        static let powerSaveMode = "powerSaveMode"
        static let capsLockMapping = "capsLockMapping"
        static let autoResumeRemote = "autoResumeRemote"
        static let knownHosts = "knownHosts"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var targetAddress: String? {
        get { defaults.string(forKey: Key.targetAddress) }
        nonmutating set { defaults.set(newValue, forKey: Key.targetAddress) }
    }

    var targetName: String? {
        get { defaults.string(forKey: Key.targetName) }
        nonmutating set { defaults.set(newValue, forKey: Key.targetName) }
    }

    var pointerMultiplier: Double {
        get {
            let stored = defaults.double(forKey: Key.pointerMultiplier)
            return stored == 0 ? PointerScaler.defaultMultiplier : stored
        }
        nonmutating set { defaults.set(newValue, forKey: Key.pointerMultiplier) }
    }

    /// Remembers that the user last chose "connect", so the app reconnects after relaunch.
    var wantsConnection: Bool {
        get { defaults.bool(forKey: Key.wantsConnection) }
        nonmutating set { defaults.set(newValue, forKey: Key.wantsConnection) }
    }

    /// True only after the user chose "disconnect" in the app; host-initiated links are refused meanwhile.
    var isPaused: Bool {
        get { defaults.bool(forKey: Key.isPaused) }
        nonmutating set { defaults.set(newValue, forKey: Key.isPaused) }
    }

    var powerSaveMode: PowerSaveMode {
        get { defaults.string(forKey: Key.powerSaveMode).flatMap(PowerSaveMode.init(rawValue:)) ?? .defaultMode }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.powerSaveMode) }
    }

    var capsLockMapping: CapsLockMapping {
        get { defaults.string(forKey: Key.capsLockMapping).flatMap(CapsLockMapping.init(rawValue:)) ?? .defaultMapping }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.capsLockMapping) }
    }

    /// Re-enter remote mode when a link that dropped during remote mode comes back (iMac wake/login).
    var autoResumeRemote: Bool {
        get { defaults.object(forKey: Key.autoResumeRemote) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.autoResumeRemote) }
    }

    /// Hosts this Mac has served before, most recent first (the device list in the menu).
    var knownHosts: KnownHosts {
        get { defaults.data(forKey: Key.knownHosts).map { KnownHosts(encoded: $0, fallbackToEmpty: true) } ?? KnownHosts() }
        nonmutating set { defaults.set(try? newValue.encoded(), forKey: Key.knownHosts) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    var hotkey: Hotkey {
        get {
            var hotkey = Hotkey.default
            // object(forKey:) distinguishes "unset" from key code 0 (the A key).
            if let stored = defaults.object(forKey: Key.hotkeyKeyCode) as? Int { hotkey.keyCode = stored }
            return hotkey
        }
        nonmutating set { defaults.set(newValue.keyCode, forKey: Key.hotkeyKeyCode) }
    }
}
