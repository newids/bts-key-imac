/// Decides whether a host-initiated HID connection should be accepted.
///
/// A bonded iMac reconnects to its keyboard on its own, e.g. when the user clicks
/// "Connect" in the iMac's Bluetooth settings or the iMac wakes. The user moves
/// between iMacs, so any paired host is accepted and becomes the new target;
/// encrypted HID channels can only come from a bonded host anyway.
public enum InboundPolicy {
    public static func shouldAccept(isPaired: Bool, isPaused: Bool) -> Bool {
        isPaired && !isPaused
    }

    public static func isSameHost(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return normalize(lhs) == normalize(rhs)
    }

    /// IOBluetooth reports "aa-aa-aa-aa-aa-01"; System Settings shows "AA:AA:AA:AA:AA:01".
    public static func normalize(_ address: String) -> String {
        String(address.lowercased().map { $0 == ":" ? "-" : $0 })
    }
}
