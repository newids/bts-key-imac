/// Which HID L2CAP channel a PSM belongs to.
///
/// Channels are identified by PSM rather than by object identity: IOBluetooth may hand a
/// host-initiated channel to the open notification and to delegate callbacks as different
/// wrapper objects, and identity checks then silently drop the host's control requests.
public enum HIDChannelRole: Equatable, Sendable {
    case control
    case interrupt

    public static let controlPSM: UInt16 = 0x0011
    public static let interruptPSM: UInt16 = 0x0013

    public init?(psm: UInt16) {
        switch psm {
        case Self.controlPSM: self = .control
        case Self.interruptPSM: self = .interrupt
        default: return nil
        }
    }
}
