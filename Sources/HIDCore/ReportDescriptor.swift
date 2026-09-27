/// USB HID report descriptor for a keyboard + mouse composite device.
/// This is the single source of truth for the byte layout used by
/// `KeyboardReport` and `MouseReport`.
public enum ReportDescriptor {
    public static let bytes: [UInt8] = keyboardCollection + mouseCollection

    private static let keyboardCollection: [UInt8] = [
        0x05, 0x01,                         // Usage Page (Generic Desktop)
        0x09, 0x06,                         // Usage (Keyboard)
        0xA1, 0x01,                         // Collection (Application)
        0x85, HIDReportID.keyboard.rawValue, //   Report ID
        0x05, 0x07,                         //   Usage Page (Keyboard/Keypad)
        0x19, 0xE0, 0x29, 0xE7,             //   Usage Min/Max (Left Control .. Right GUI)
        0x15, 0x00, 0x25, 0x01,             //   Logical Min/Max (0, 1)
        0x75, 0x01, 0x95, 0x08,             //   Report Size 1, Count 8
        0x81, 0x02,                         //   Input (Data, Var, Abs) — modifiers
        0x95, 0x01, 0x75, 0x08,             //   Count 1, Size 8
        0x81, 0x01,                         //   Input (Const) — reserved byte
        0x05, 0x08,                         //   Usage Page (LEDs)
        0x19, 0x01, 0x29, 0x05,             //   Usage Min/Max (Num Lock .. Kana)
        0x95, 0x05, 0x75, 0x01,             //   Count 5, Size 1
        0x91, 0x02,                         //   Output (Data, Var, Abs) — LEDs
        0x95, 0x01, 0x75, 0x03,             //   Count 1, Size 3
        0x91, 0x01,                         //   Output (Const) — padding
        0x05, 0x07,                         //   Usage Page (Keyboard/Keypad)
        0x19, 0x00, 0x29, 0xFF,             //   Usage Min/Max (0 .. 255)
        0x15, 0x00, 0x26, 0xFF, 0x00,       //   Logical Min/Max (0, 255)
        0x95, 0x06, 0x75, 0x08,             //   Count 6, Size 8
        0x81, 0x00,                         //   Input (Data, Array) — 6 key codes
        0x05, 0xFF,                         //   Usage Page (Apple vendor top case)
        0x09, 0x03,                         //   Usage (Keyboard Fn / 🌐)
        0x15, 0x00, 0x25, 0x01,             //   Logical Min/Max (0, 1)
        0x75, 0x08, 0x95, 0x01,             //   Size 8, Count 1
        0x81, 0x02,                         //   Input (Data, Var, Abs) — Fn byte, 1 = down
        0xC0,                               // End Collection
    ]

    private static let mouseCollection: [UInt8] = [
        0x05, 0x01,                         // Usage Page (Generic Desktop)
        0x09, 0x02,                         // Usage (Mouse)
        0xA1, 0x01,                         // Collection (Application)
        0x85, HIDReportID.mouse.rawValue,   //   Report ID
        0x09, 0x01,                         //   Usage (Pointer)
        0xA1, 0x00,                         //   Collection (Physical)
        0x05, 0x09,                         //     Usage Page (Button)
        0x19, 0x01, 0x29, 0x03,             //     Usage Min/Max (Button 1 .. 3)
        0x15, 0x00, 0x25, 0x01,             //     Logical Min/Max (0, 1)
        0x95, 0x03, 0x75, 0x01,             //     Count 3, Size 1
        0x81, 0x02,                         //     Input (Data, Var, Abs) — buttons
        0x95, 0x01, 0x75, 0x05,             //     Count 1, Size 5
        0x81, 0x03,                         //     Input (Const) — padding
        0x05, 0x01,                         //     Usage Page (Generic Desktop)
        0x09, 0x30, 0x09, 0x31,             //     Usage X, Usage Y
        0x16, 0x01, 0x80,                   //     Logical Min (-32767)
        0x26, 0xFF, 0x7F,                   //     Logical Max (32767)
        0x75, 0x10, 0x95, 0x02,             //     Size 16, Count 2
        0x81, 0x06,                         //     Input (Data, Var, Rel) — X, Y
        0x09, 0x38,                         //     Usage (Wheel)
        0x15, 0x81, 0x25, 0x7F,             //     Logical Min/Max (-127, 127)
        0x75, 0x08, 0x95, 0x01,             //     Size 8, Count 1
        0x81, 0x06,                         //     Input (Data, Var, Rel) — wheel
        0x05, 0x0C,                         //     Usage Page (Consumer)
        0x0A, 0x38, 0x02,                   //     Usage (AC Pan)
        0x15, 0x81, 0x25, 0x7F,             //     Logical Min/Max (-127, 127)
        0x75, 0x08, 0x95, 0x01,             //     Size 8, Count 1
        0x81, 0x06,                         //     Input (Data, Var, Rel) — horizontal pan
        0xC0,                               //   End Collection
        0xC0,                               // End Collection
    ]
}
