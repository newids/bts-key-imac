import Foundation
import IOKit.hid
import os

/// Reports the physical Caps Lock key's down/up edges from IOKit HID.
///
/// With "Caps Lock switches input sources" enabled, a short tap never changes the
/// Caps Lock flag, so a CGEvent tap cannot tell press from release. Forwarding the
/// real down/up edges makes the iMac see a normal key tap and switch 한/영.
/// Needs Input Monitoring, which the event tap already requires.
public final class CapsLockMonitor {
    private static let keyboardUsagePage = UInt32(kHIDPage_KeyboardOrKeypad)
    private static let capsLockUsage = UInt32(kHIDUsage_KeyboardCapsLock)

    public var onChange: ((Bool) -> Void)?
    private let log = Logger(subsystem: "btskey", category: "input-capture")
    private var manager: IOHIDManager?

    public init() {}

    public var isRunning: Bool { manager != nil }

    @discardableResult
    public func start() -> Bool {
        guard manager == nil else { return true }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerSetInputValueMatching(manager, [
            kIOHIDElementUsagePageKey: Self.keyboardUsagePage,
            kIOHIDElementUsageKey: Self.capsLockUsage,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let monitor = Unmanaged<CapsLockMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.onChange?(IOHIDValueGetIntegerValue(value) != 0)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            log.error("Caps Lock monitor could not open HID manager: \(status, privacy: .public)")
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return false
        }
        self.manager = manager
        return true
    }

    public func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }
}
