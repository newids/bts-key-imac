/// Where the user's keystrokes currently go.
public enum SessionState: Equatable, Sendable {
    case idle
    case connecting
    case connectedLocal
    case connectedRemote
    case disconnected
}

public enum SessionEvent: Equatable, Sendable {
    case connectRequested
    case transportConnected
    case transportDisconnected
    case toggleRequested
    case screenLocked
    case appWillTerminate
    case stopRequested
}

public enum HUDMessage: Equatable, Sendable {
    case connected
    case remote
    case local
    case disconnected
}

/// Side effects the app shell must perform after a transition.
public enum SessionEffect: Equatable, Sendable {
    case sendAllUp
    case lockCursor
    case unlockCursor
    case showHUD(HUDMessage)
}

/// Pure reducer for the local/remote mode switch (requirement 3).
/// Every path out of remote mode releases keys and the cursor, so the MacBook
/// can never be left without input control.
public struct SessionStateMachine: Sendable {
    public private(set) var state: SessionState

    public init(state: SessionState = .idle) {
        self.state = state
    }

    public var isCapturing: Bool { state == .connectedRemote }

    @discardableResult
    public mutating func handle(_ event: SessionEvent) -> [SessionEffect] {
        switch (state, event) {
        case (.idle, .connectRequested), (.disconnected, .connectRequested):
            state = .connecting
            return []
        case (.connecting, .transportConnected), (.disconnected, .transportConnected), (.idle, .transportConnected):
            // `.idle` covers a host-initiated connection that arrives before the user pressed connect.
            state = .connectedLocal
            return [.showHUD(.connected)]
        case (.connectedLocal, .toggleRequested):
            state = .connectedRemote
            return [.lockCursor, .showHUD(.remote)]
        case (.connectedRemote, .toggleRequested):
            state = .connectedLocal
            return [.sendAllUp, .unlockCursor, .showHUD(.local)]
        case (.connectedRemote, .screenLocked), (.connectedRemote, .appWillTerminate):
            state = .connectedLocal
            return [.sendAllUp, .unlockCursor, .showHUD(.local)]
        case (.connectedRemote, .transportDisconnected):
            state = .disconnected
            return [.unlockCursor, .showHUD(.disconnected)]
        case (.connectedLocal, .transportDisconnected), (.connecting, .transportDisconnected):
            state = .disconnected
            return [.showHUD(.disconnected)]
        case (.connectedRemote, .stopRequested):
            state = .idle
            return [.sendAllUp, .unlockCursor]
        case (_, .stopRequested):
            state = .idle
            return []
        default:
            return []
        }
    }
}
