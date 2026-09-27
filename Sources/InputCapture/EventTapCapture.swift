import AppKit
import CoreGraphics
import HIDCore
import os

/// Captures keyboard and trackpad input with a session-level CGEvent tap.
///
/// - When `isCapturing` is false, every event passes through untouched except the toggle hotkey.
/// - When `isCapturing` is true, events are swallowed locally and turned into HID reports.
/// Mouse motion is coalesced into a fixed tick (125 Hz) and never dropped; button
/// changes are flushed immediately. Pointer deltas come from the post-acceleration
/// CGEvent values so movement feels like the local trackpad.
public final class EventTapCapture {
    public static let mouseTickInterval: TimeInterval = 0.008
    private static let pixelsPerScrollNotch = 10.0
    private static let capsLockKeyCode: Int64 = 57
    /// kVK_Function: the MacBook's fn/🌐 key.
    private static let functionKeyCode: Int64 = 63

    public var onKeyboardReport: ((KeyboardReport) -> Void)?
    public var onMouseReport: ((MouseReport) -> Void)?
    public var onHotkey: (() -> Void)?
    public var onTapDisabled: (() -> Void)?
    /// Called for every swallowed motion event so the local pointer can be pinned in place.
    public var onPointerMotion: (() -> Void)?

    public var hotkey: Hotkey = .default
    public var pointerScaler = PointerScaler()
    public var capsLockMapping = CapsLockMapping.defaultMapping
    public var isCapturing = false {
        didSet {
            guard isCapturing != oldValue else { return }
            stateLock.lock()
            isCapturingForTimer = isCapturing
            stateLock.unlock()
            if isCapturing {
                startMouseTimer()
            } else {
                // The 125 Hz timer only runs in remote mode, so an idle app costs no wakeups.
                stopMouseTimer()
                resetState()
            }
        }
    }

    private let log = Logger(subsystem: "btskey", category: "input-capture")
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mouseTimer: DispatchSourceTimer?
    private let stateLock = NSLock()
    private var keyboard = KeyboardState()
    private var mouse = MouseAccumulator()
    private var swallowHotkeyKeyUp = false
    private let capsLock = CapsLockMonitor()
    /// Mirror of `isCapturing` read by the timer queue under `stateLock`.
    private var isCapturingForTimer = false

    public init() {}

    deinit { stop() }

    public var isRunning: Bool { tap != nil }

    public func start() throws {
        guard tap == nil else { return }
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .scrollWheel,
        ]
        let mask: CGEventMask = types.reduce(0) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let capture = Unmanaged<EventTapCapture>.fromOpaque(userInfo).takeUnretainedValue()
                return capture.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            throw CaptureError.tapCreationFailed
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        capsLock.onChange = { [weak self] isDown in self?.handleCapsLock(isDown: isDown) }
        if !capsLock.start() {
            log.error("Caps Lock falls back to flag changes; 한/영 taps may not reach the host")
        }
        if isCapturing { startMouseTimer() }
        log.notice("event tap started")
    }

    public func stop() {
        stopMouseTimer()
        capsLock.stop()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
        resetState()
    }

    /// Emits a zero keyboard report and clears held state; used when leaving remote mode.
    public func releaseAll() {
        stateLock.lock()
        keyboard.allUp()
        let report = keyboard.report
        stateLock.unlock()
        onKeyboardReport?(report)
    }

    public enum CaptureError: LocalizedError {
        case tapCreationFailed
        public var errorDescription: String? {
            "Could not create the event tap. Grant Accessibility and Input Monitoring permission and try again."
        }
    }

    // MARK: - Event handling (runs on the main run loop)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onTapDisabled?()
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            return handleKey(type: type, event: event)
        case .flagsChanged:
            return isCapturing ? handleFlagsChanged(event) : Unmanaged.passUnretained(event)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard isCapturing else { return Unmanaged.passUnretained(event) }
            handleMotion(event)
            return nil
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            guard isCapturing else { return Unmanaged.passUnretained(event) }
            handleButton(type: type, event: event)
            return nil
        case .scrollWheel:
            guard isCapturing else { return Unmanaged.passUnretained(event) }
            handleScroll(event)
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if type == .keyDown, hotkey.matches(keyCode: keyCode, flags: event.flags) {
            // Holding the chord must not flap the mode: only the first keyDown toggles.
            if !isAutorepeat {
                swallowHotkeyKeyUp = true
                onHotkey?()
            }
            return nil
        }
        if type == .keyUp, swallowHotkeyKeyUp, keyCode == hotkey.keyCode {
            swallowHotkeyKeyUp = false
            return nil
        }
        guard isCapturing else { return Unmanaged.passUnretained(event) }
        if isAutorepeat { return nil }
        guard let usage = MacKeycodeMap.usage(forVirtualKey: keyCode) else { return nil }

        stateLock.lock()
        if type == .keyDown { keyboard.press(usage) } else { keyboard.release(usage) }
        let report = keyboard.report
        stateLock.unlock()
        onKeyboardReport?(report)
        return nil
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        stateLock.lock()
        keyboard.modifiers = ModifierTranslator.modifiers(from: event.flags)
        var reports = [keyboard.report]
        if keyCode == Self.capsLockKeyCode, capsLock.isRunning {
            // The HID monitor forwards the real down/up edges; the flag change carries no timing.
            stateLock.unlock()
            return nil
        }
        if keyCode == Self.capsLockKeyCode {
            // Fallback without the HID monitor: the flag change carries no timing, so emit a tap.
            reports = capsLockMapping.reports(isDown: true, state: &keyboard)
                + capsLockMapping.reports(isDown: false, state: &keyboard)
        } else if keyCode == Self.functionKeyCode {
            keyboard.setFn(held: event.flags.contains(.maskSecondaryFn), by: .fnKey)
            reports = [keyboard.report]
        }
        stateLock.unlock()
        reports.forEach { onKeyboardReport?($0) }
        return nil
    }

    private func handleCapsLock(isDown: Bool) {
        guard isCapturing else { return }
        stateLock.lock()
        let reports = capsLockMapping.reports(isDown: isDown, state: &keyboard)
        stateLock.unlock()
        reports.forEach { onKeyboardReport?($0) }
    }

    private func handleMotion(_ event: CGEvent) {
        onPointerMotion?()
        let dx = Double(event.getIntegerValueField(.mouseEventDeltaX))
        let dy = Double(event.getIntegerValueField(.mouseEventDeltaY))
        let scaled = pointerScaler.scale(dx: dx, dy: dy)
        stateLock.lock()
        mouse.addMovement(dx: scaled.dx, dy: scaled.dy)
        stateLock.unlock()
    }

    private func handleButton(type: CGEventType, event: CGEvent) {
        let button: MouseButtons
        switch type {
        case .leftMouseDown, .leftMouseUp: button = .left
        case .rightMouseDown, .rightMouseUp: button = .right
        default: button = .middle
        }
        let pressed = [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type)
        stateLock.lock()
        mouse.setButton(button, pressed: pressed)
        let report = mouse.drain()
        stateLock.unlock()
        onMouseReport?(report)
    }

    private func handleScroll(_ event: CGEvent) {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let wheel: Double
        let pan: Double
        if isContinuous {
            wheel = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)) / Self.pixelsPerScrollNotch
            pan = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)) / Self.pixelsPerScrollNotch
        } else {
            wheel = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            pan = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        }
        stateLock.lock()
        mouse.addScroll(wheel: wheel, pan: pan)
        stateLock.unlock()
    }

    private func startMouseTimer() {
        guard mouseTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "btskey.mouse-tick", qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: Self.mouseTickInterval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.flushMouse() }
        timer.resume()
        mouseTimer = timer
    }

    private func stopMouseTimer() {
        mouseTimer?.cancel()
        mouseTimer = nil
    }

    private func flushMouse() {
        stateLock.lock()
        guard isCapturingForTimer, mouse.hasPendingMovement else { stateLock.unlock(); return }
        let report = mouse.drain()
        stateLock.unlock()
        onMouseReport?(report)
    }

    private func resetState() {
        stateLock.lock()
        keyboard = KeyboardState()
        mouse = MouseAccumulator()
        swallowHotkeyKeyUp = false
        stateLock.unlock()
    }
}
