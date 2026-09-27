import Foundation

/// A dedicated high-priority thread with its own run loop for the event tap and HID monitors.
///
/// The tap must never live on the main thread: IOBluetooth calls there can block for
/// seconds, and while the tap's run loop is stalled macOS holds *all* keyboard and
/// mouse events system-wide until it gives up and disables the tap.
public final class InputThread {
    public static let shared = InputThread()

    private let thread: Thread
    private let ready = DispatchSemaphore(value: 0)
    private var loop: CFRunLoop?

    private init() {
        let ready = self.ready
        let box = LoopBox()
        thread = Thread {
            box.loop = CFRunLoopGetCurrent()
            ready.signal()
            // Keep the loop alive with a far-future timer; sources are added later.
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), CFRunLoopTimerCreate(nil, .greatestFiniteMagnitude, 0, 0, 0, nil, nil), .commonModes)
            CFRunLoopRun()
        }
        thread.name = "btskey.input"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        loop = box.loop
    }

    private final class LoopBox {
        var loop: CFRunLoop?
    }

    public var runLoop: CFRunLoop { loop! }

    /// Runs `body` on the input thread and waits for it, so run-loop sources are always
    /// added and removed from their own thread.
    public func sync(_ body: @escaping () -> Void) {
        if Thread.current == thread { body(); return }
        let done = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            body()
            done.signal()
        }
        CFRunLoopWakeUp(runLoop)
        done.wait()
    }
}
