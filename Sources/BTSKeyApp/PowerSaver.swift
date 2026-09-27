import CoreGraphics
import Foundation
import HIDCore
import os

/// Dims the MacBook's built-in display while its input goes to the iMac, and restores it afterwards.
///
/// Uses DisplayServices (private, resolved at runtime) because the public API cannot set
/// backlight brightness. If it is unavailable the mode silently does nothing.
/// The brightness to restore is persisted, so a crash while dimmed is repaired on next launch.
final class PowerSaver {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let savedKey = "powerSaverSavedBrightness"
    /// Auto-brightness can creep back up; re-apply while active.
    private static let reapplyInterval: TimeInterval = 5

    private let log = Logger(subsystem: "btskey", category: "power")
    private let defaults: UserDefaults
    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private var activeMode: PowerSaveMode = .off
    private var reapplyTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        getBrightness = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetBrightness.self) }
        setBrightness = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetBrightness.self) }
        restoreAfterCrash()
    }

    var isAvailable: Bool { getBrightness != nil && setBrightness != nil && builtInDisplay != nil }

    func enter(_ mode: PowerSaveMode) {
        guard mode != .off, activeMode == .off, let display = builtInDisplay, let current = readBrightness(display) else { return }
        guard let target = mode.brightness(forCurrent: Double(current)) else { return }
        defaults.set(Double(current), forKey: Self.savedKey)
        activeMode = mode
        apply(Float(target), to: display)
        let timer = Timer(timeInterval: Self.reapplyInterval, repeats: true) { [weak self] _ in
            guard let self, let display = self.builtInDisplay, let now = self.readBrightness(display),
                  let target = self.activeMode.targetBrightness, Double(now) > target + 0.01 else { return }
            self.apply(Float(target), to: display)
        }
        RunLoop.main.add(timer, forMode: .common)
        reapplyTimer = timer
        log.notice("power save \(mode.rawValue, privacy: .public): brightness \(current, privacy: .public) -> \(target, privacy: .public)")
    }

    func exit() {
        reapplyTimer?.invalidate()
        reapplyTimer = nil
        guard activeMode != .off else { return }
        activeMode = .off
        restoreSaved()
    }

    private func restoreAfterCrash() {
        if defaults.object(forKey: Self.savedKey) != nil {
            log.notice("restoring brightness left dimmed by a previous run")
            restoreSaved()
        }
    }

    private func restoreSaved() {
        guard let saved = defaults.object(forKey: Self.savedKey) as? Double else { return }
        // Keep the saved value until the restore verifiably succeeds, so a failure is retried next launch.
        guard let display = builtInDisplay, apply(Float(saved), to: display) else {
            log.error("brightness restore deferred: built-in display unavailable or refused")
            return
        }
        defaults.removeObject(forKey: Self.savedKey)
    }

    private var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 8)
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private func readBrightness(_ display: CGDirectDisplayID) -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        return getBrightness(display, &value) == 0 ? value : nil
    }

    @discardableResult
    private func apply(_ value: Float, to display: CGDirectDisplayID) -> Bool {
        guard let setBrightness else { return false }
        let status = setBrightness(display, value)
        if status != 0 { log.error("DisplayServicesSetBrightness failed: \(status, privacy: .public)") }
        return status == 0
    }
}
