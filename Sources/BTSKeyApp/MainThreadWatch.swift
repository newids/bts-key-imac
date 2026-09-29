import Foundation
import os

/// Logs when the main thread stops servicing its run loop. IOBluetooth calls that wait
/// synchronously freeze the menu and every timer of the app; the log shows when and for how long,
/// next to the connection step that caused it.
final class MainThreadWatch {
    private static let interval: TimeInterval = 0.25
    private static let reportThreshold: TimeInterval = 0.75

    private let log = Logger(subsystem: "btskey", category: "main-thread")
    private var timer: Timer?
    private var lastTick = Date()

    func start() {
        guard timer == nil else { return }
        lastTick = Date()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()
        let gap = now.timeIntervalSince(lastTick)
        lastTick = now
        guard gap > Self.reportThreshold else { return }
        log.error("main thread stalled for \(String(format: "%.2f", gap), privacy: .public)s")
    }
}
