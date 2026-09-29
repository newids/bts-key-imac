/// What the HUD needs to know besides the message itself.
public struct HUDContext: Equatable, Sendable {
    public let hostName: String?
    public let hotkey: String

    public init(hostName: String?, hotkey: String) {
        self.hostName = hostName
        self.hotkey = hotkey
    }
}

/// What the overlay shows for a message: wording, symbol, colour family and how long it stays.
/// Kept here, away from AppKit, so the wording and the reading time are covered by tests.
public struct HUDPresentation: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        case progress, success, remote, local, warning, notice
    }

    /// Shortest time any message stays up. One second, then 1.6 s, were too short to notice;
    /// the overlay now shows the time left and can be closed, so it can afford to stay.
    public static let minimumDuration: Double = 4
    private static let connectionChangeDuration: Double = 6
    private static let problemDuration: Double = 9
    /// Longer than the transport's connect watchdog: progress stays until a result replaces it.
    private static let progressDuration: Double = 24
    private static let fallbackHostName = "iMac"

    public let title: String
    public let detail: String?
    /// SF Symbol name; nil means "show a spinner".
    public let symbolName: String?
    public let tone: Tone
    public let duration: Double

    /// Whether the time left is shown as a gauge. Progress has no known end, so it has none.
    public var showsCountdown: Bool { tone != .progress }

    public init(_ message: HUDMessage, context: HUDContext) {
        let host = context.hostName ?? Self.fallbackHostName
        switch message {
        case .connecting(let isFirstConnection):
            title = "\(host)에 연결 중"
            detail = isFirstConnection ? "처음 연결하는 iMac입니다" : "이전에 연결했던 iMac입니다"
            symbolName = nil
            tone = .progress
            duration = Self.progressDuration
        case .connected:
            title = "\(host) 연결됨"
            detail = "\(context.hotkey)로 입력을 iMac으로 보냅니다"
            symbolName = "checkmark"
            tone = .success
            duration = Self.connectionChangeDuration
        case .remote:
            title = "iMac 입력"
            detail = "\(context.hotkey)로 MacBook으로 돌아옵니다"
            symbolName = "desktopcomputer"
            tone = .remote
            duration = Self.minimumDuration
        case .local:
            title = "MacBook 입력"
            detail = "키보드와 트랙패드가 이 Mac을 조작합니다"
            symbolName = "laptopcomputer"
            tone = .local
            duration = Self.minimumDuration
        case .disconnected(let followUp):
            title = "연결 끊김"
            detail = Self.detail(for: followUp)
            symbolName = "bolt.horizontal"
            tone = .warning
            duration = Self.problemDuration
        case .pairedNewHost(let name):
            title = "새 iMac 페어링됨"
            detail = "\(name)에 연결합니다"
            symbolName = "link"
            tone = .notice
            duration = Self.connectionChangeDuration
        }
    }

    private static func detail(for followUp: DisconnectFollowUp) -> String? {
        switch followUp {
        case .none: return nil
        case .retrying(let seconds): return "\(seconds)초 뒤 한 번 더 시도합니다"
        case .waitingForUser: return "메뉴에서 ‘지금 다시 연결’을 누르세요"
        case .hostClosed: return "iMac이 연결을 해제했습니다"
        }
    }
}
