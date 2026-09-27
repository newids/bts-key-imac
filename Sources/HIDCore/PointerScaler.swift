/// Applies the user's sensitivity multiplier to pointer deltas.
public struct PointerScaler: Sendable {
    public static let minimumMultiplier = 0.5
    public static let maximumMultiplier = 4.0
    public static let defaultMultiplier = 1.5

    public let multiplier: Double

    public init(multiplier: Double = PointerScaler.defaultMultiplier) {
        self.multiplier = min(max(multiplier, Self.minimumMultiplier), Self.maximumMultiplier)
    }

    public func scale(dx: Double, dy: Double) -> (dx: Double, dy: Double) {
        (dx * multiplier, dy * multiplier)
    }
}
