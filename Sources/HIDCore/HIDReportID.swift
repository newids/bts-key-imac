/// Report IDs shared by the report descriptor, the encoders and the transports.
public enum HIDReportID: UInt8, Sendable {
    /// Keyboard input report (8 bytes) and LED output report (1 byte).
    case keyboard = 1
    /// Mouse input report (7 bytes): buttons, Int16 X, Int16 Y, Int8 wheel, Int8 pan.
    case mouse = 2
}
