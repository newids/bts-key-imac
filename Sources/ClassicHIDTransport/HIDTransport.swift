import Foundation
import HIDCore

public protocol HIDTransportDelegate: AnyObject {
    /// `hostAddress`/`hostName` identify the host on the other end (it may differ from `targetAddress` for a host-initiated link).
    func transportDidConnect(_ transport: HIDTransport, hostAddress: String, hostName: String?)
    /// `error` is nil when the link was closed on purpose (user disconnect or quit).
    func transportDidDisconnect(_ transport: HIDTransport, error: HIDTransportError?)
}

/// Abstraction over the Bluetooth link so the app shell does not care whether
/// reports travel over Classic HID (plan A) or BLE HOGP (plan B).
public protocol HIDTransport: AnyObject {
    var delegate: HIDTransportDelegate? { get set }
    var isConnected: Bool { get }
    /// Host allowed to connect in, and the default outbound target ("xx-xx-xx-xx-xx-xx" or "XX:XX:…").
    var targetAddress: String? { get set }
    /// When true, host-initiated connections are refused (the user chose "disconnect" in the app).
    var isPaused: Bool { get set }

    /// Publishes the HID service once and starts listening for host-initiated connections.
    func start()
    /// Opens the link to `targetAddress` from this side.
    func connect()
    /// Closes the link but stays published, so the host cannot fall back to treating this Mac as its own input device.
    func disconnect()
    /// Removes the service record; call once on quit.
    func shutdown()
    func send(reportID: HIDReportID, payload: [UInt8])
}

public enum HIDTransportError: LocalizedError, Equatable {
    case noTarget
    case notPublished
    case invalidAddress(String)
    case notPaired(String)
    case publishFailed
    case connectionFailed(code: Int32)
    case channelOpenFailed(psm: UInt16, code: Int32)
    case timedOut
    case linkClosed
    case hostUnplugged

    /// Whether retrying later can succeed without the user changing anything.
    public var isRetryable: Bool {
        switch self {
        case .noTarget, .invalidAddress, .notPaired, .publishFailed, .hostUnplugged: return false
        case .notPublished, .connectionFailed, .channelOpenFailed, .timedOut, .linkClosed: return true
        }
    }

    public var errorDescription: String? {
        switch self {
        case .noTarget: return "대상 iMac을 먼저 선택하세요."
        case .invalidAddress(let address): return "잘못된 블루투스 주소: \(address)"
        case .notPaired(let name): return "\(name)과(와) 페어링되어 있지 않습니다. 시스템 설정 → Bluetooth에서 먼저 페어링하세요."
        case .notPublished: return "HID 서비스 등록을 기다리는 중입니다."
        case .publishFailed: return "HID 서비스를 등록하지 못했습니다. 다른 키보드 에뮬레이터(KeyPad 등)를 종료한 뒤 앱을 다시 실행하세요."
        case .connectionFailed(let code): return "iMac에 연결하지 못했습니다(잠자기 또는 범위 밖일 수 있음, IOReturn \(code))."
        case .channelOpenFailed(let psm, let code): return "HID 채널 0x\(String(psm, radix: 16))을 열지 못했습니다(IOReturn \(code))."
        case .timedOut: return "연결 시간이 초과되었습니다."
        case .linkClosed: return "블루투스 연결이 끊겼습니다."
        case .hostUnplugged: return "iMac이 이 키보드의 연결을 해제했습니다."
        }
    }
}
