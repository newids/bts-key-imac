/// Button bits of the mouse input report.
public struct MouseButtons: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let left = MouseButtons(rawValue: 0x01)
    public static let right = MouseButtons(rawValue: 0x02)
    public static let middle = MouseButtons(rawValue: 0x04)
}

/// Mouse input report: buttons, Int16 X, Int16 Y, Int8 wheel, Int8 horizontal pan.
public struct MouseReport: Equatable, Sendable {
    public static let byteCount = 7

    public var buttons: MouseButtons
    public var dx: Int16
    public var dy: Int16
    public var wheel: Int8
    public var pan: Int8

    public init(buttons: MouseButtons = [], dx: Int16 = 0, dy: Int16 = 0, wheel: Int8 = 0, pan: Int8 = 0) {
        self.buttons = buttons
        self.dx = dx
        self.dy = dy
        self.wheel = wheel
        self.pan = pan
    }

    public var bytes: [UInt8] {
        [
            buttons.rawValue,
            UInt8(truncatingIfNeeded: dx), UInt8(truncatingIfNeeded: dx >> 8),
            UInt8(truncatingIfNeeded: dy), UInt8(truncatingIfNeeded: dy >> 8),
            UInt8(bitPattern: wheel),
            UInt8(bitPattern: pan),
        ]
    }
}

/// Accumulates pointer motion between transport ticks so nothing is dropped
/// when events arrive faster than reports are sent. Fractional remainders are
/// carried over so slow, fine movement is not lost to integer truncation.
public struct MouseAccumulator: Sendable {
    private var dx: Double = 0
    private var dy: Double = 0
    private var wheel: Double = 0
    private var pan: Double = 0
    public private(set) var buttons: MouseButtons = []

    public init() {}

    public var hasPendingMovement: Bool {
        abs(dx) >= 1 || abs(dy) >= 1 || abs(wheel) >= 1 || abs(pan) >= 1
    }

    public mutating func addMovement(dx: Double, dy: Double) {
        self.dx += dx
        self.dy += dy
    }

    public mutating func addScroll(wheel: Double, pan: Double) {
        self.wheel += wheel
        self.pan += pan
    }

    public mutating func setButton(_ button: MouseButtons, pressed: Bool) {
        if pressed { buttons.insert(button) } else { buttons.remove(button) }
    }

    /// Returns the report for everything accumulated so far and keeps only the fractional remainders.
    public mutating func drain() -> MouseReport {
        let report = MouseReport(
            buttons: buttons,
            dx: Self.takeInt16(&dx),
            dy: Self.takeInt16(&dy),
            wheel: Self.takeInt8(&wheel),
            pan: Self.takeInt8(&pan)
        )
        return report
    }

    private static func takeInt16(_ value: inout Double) -> Int16 {
        let whole = value.rounded(.towardZero)
        value -= whole
        let limit = Double(Int16.max)
        return Int16(min(max(whole, -limit), limit))
    }

    private static func takeInt8(_ value: inout Double) -> Int8 {
        let whole = value.rounded(.towardZero)
        value -= whole
        let limit = Double(Int8.max)
        return Int8(min(max(whole, -limit), limit))
    }
}
