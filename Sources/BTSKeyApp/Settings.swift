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
        static let capsLockMapping = "capsLockMapping"          // the single choice of 0.1.x, read once
        static let capsLockPreferences = "capsLockPreferences"
        static let autoResumeRemote = "autoResumeRemote"
        static let knownHosts = "knownHosts"
        static let pairingLedger = "pairedDeviceLedger"   // every paired device, not only computers
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

    /// What Caps Lock becomes, per host. Starts from the single choice earlier versions stored.
    var capsLockPreferences: CapsLockPreferences {
        get {
            if let data = defaults.data(forKey: Key.capsLockPreferences),
               let stored = try? JSONDecoder().decode(CapsLockPreferences.self, from: data) {
                return stored
            }
            let earlier = defaults.string(forKey: Key.capsLockMapping).flatMap(CapsLockMapping.init(rawValue:))
            return CapsLockPreferences(general: earlier ?? .defaultMapping)
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.capsLockPreferences) }
    }

    /// The choice in effect for the current target.
    var capsLockMapping: CapsLockMapping {
        capsLockPreferences.mapping(for: targetAddress)
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

    /// When each pairing was first seen, kept across launches so a pairing made while the app
    /// was not running still counts as new.
    var pairingLedger: PairingLedger {
        get { defaults.data(forKey: Key.pairingLedger).flatMap { try? JSONDecoder().decode(PairingLedger.self, from: $0) } ?? PairingLedger() }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.pairingLedger) }
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
