/// How much to save power on the MacBook while its input goes to the iMac.
/// The MacBook screen shows nothing useful then, so the built-in display is dimmed.
public enum PowerSaveMode: String, CaseIterable, Sendable {
    case off
    case dim
    case blank

    public static let defaultMode = PowerSaveMode.dim

    /// Built-in display brightness (0...1) to apply in remote mode, or nil to leave it alone.
    public var targetBrightness: Double? {
        switch self {
        case .off: return nil
        case .dim: return 0.1
        case .blank: return 0.0
        }
    }

    /// Brightness to apply given the current one; never brightens a screen that is already darker.
    public func brightness(forCurrent current: Double) -> Double? {
        targetBrightness.map { min($0, current) }
    }
}
