/// How far up the Bluetooth stack the link to a host currently reaches.
///
/// System Settings shows "Connected" as soon as the baseband link exists, but keystrokes only
/// flow once both HID channels are open, so the two must be reported separately.
public enum LinkLayerStatus: Equatable, Sendable {
    case notPaired
    /// Bonded, no radio link.
    case pairedOnly
    /// Radio link up (what System Settings calls connected), HID channels not open.
    case basebandOnly
    /// Both HID channels open: the host sees a working keyboard.
    case hidReady

    public init(isPaired: Bool, isBasebandUp: Bool, areHIDChannelsOpen: Bool) {
        if areHIDChannelsOpen {
            self = .hidReady
        } else if !isPaired {
            self = .notPaired
        } else {
            self = isBasebandUp ? .basebandOnly : .pairedOnly
        }
    }

    public var looksConnectedInSystemSettings: Bool { self == .basebandOnly || self == .hidReady }
    public var canType: Bool { self == .hidReady }
}
