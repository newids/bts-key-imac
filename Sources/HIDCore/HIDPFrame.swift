/// Bluetooth HID Profile (HIDP) message framing used on the L2CAP control and interrupt channels.
public enum HIDPFrame {
    public enum ProtocolMode: UInt8, Equatable, Sendable {
        case boot = 0
        case report = 1
    }

    public enum ReportType: UInt8, Equatable, Sendable {
        case other = 0
        case input = 1
        case output = 2
        case feature = 3
    }

    public enum HandshakeResult: UInt8, Sendable {
        case successful = 0x00
        case notReady = 0x01
        case invalidReportID = 0x02
        case unsupportedRequest = 0x03
        case invalidParameter = 0x04
        case unknown = 0x0E
        case fatal = 0x0F
    }

    /// Messages a host may send on the control channel.
    public enum ControlMessage: Equatable, Sendable {
        case virtualCableUnplug
        case suspend
        case exitSuspend
        case getReport(type: ReportType, reportID: UInt8?)
        case setReport(type: ReportType, payload: [UInt8])
        case getProtocol
        case setProtocol(ProtocolMode)
        case dataOutput([UInt8])
        case unknown
    }

    private enum MessageType: UInt8 {
        case handshake = 0x0
        case hidControl = 0x1
        case getReport = 0x4
        case setReport = 0x5
        case getProtocol = 0x6
        case setProtocol = 0x7
        case data = 0xA
    }

    private static let dataInputHeader: UInt8 = 0xA1
    private static let controlSuspend: UInt8 = 0x03
    private static let controlExitSuspend: UInt8 = 0x04
    private static let controlVirtualCableUnplug: UInt8 = 0x05

    /// Builds a DATA (Input) frame for the interrupt channel.
    public static func dataInput(reportID: HIDReportID, payload: [UInt8]) -> [UInt8] {
        [dataInputHeader, reportID.rawValue] + payload
    }

    /// Builds a HANDSHAKE frame for the control channel.
    public static func handshake(_ result: HandshakeResult) -> [UInt8] {
        [result.rawValue]
    }

    public static func parse(_ bytes: [UInt8]) -> ControlMessage {
        guard let header = bytes.first, let type = MessageType(rawValue: header >> 4) else { return .unknown }
        let parameter = header & 0x0F
        let payload = Array(bytes.dropFirst())
        switch type {
        case .hidControl:
            switch parameter {
            case controlSuspend: return .suspend
            case controlExitSuspend: return .exitSuspend
            case controlVirtualCableUnplug: return .virtualCableUnplug
            default: return .unknown
            }
        case .getReport:
            guard let reportType = ReportType(rawValue: parameter & 0x03) else { return .unknown }
            return .getReport(type: reportType, reportID: payload.first)
        case .setReport:
            guard let reportType = ReportType(rawValue: parameter & 0x03) else { return .unknown }
            return .setReport(type: reportType, payload: payload)
        case .getProtocol:
            return .getProtocol
        case .setProtocol:
            guard let mode = ProtocolMode(rawValue: parameter & 0x01) else { return .unknown }
            return .setProtocol(mode)
        case .data:
            return .dataOutput(payload)
        case .handshake:
            return .unknown
        }
    }
}
