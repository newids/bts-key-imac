import Foundation
import IOBluetooth
import HIDCore
import os

/// Bluetooth Classic HID device emulation (plan A).
///
/// Lifecycle, derived from bluetoothd logs of this Mac talking to the target iMac:
/// - The SDP record is published once for the life of the app. Publishing it makes
///   bluetoothd route the HID PSMs (0x11/0x13) to this process; removing and
///   re-publishing it leaves the PSMs registered and the next publish fails.
/// - The host (iMac) reconnects to its bonded keyboard on its own. Those inbound
///   channels are accepted here; without a published record, macOS' own HID host
///   grabs them and treats the iMac as an input device.
/// - This side can also open both channels outbound to a bonded host.
///
/// IOBluetooth only works on the thread whose run loop services it (objects used
/// from another thread fail with kIOReturnError), so everything runs on main.
public final class ClassicHIDTransport: NSObject, HIDTransport {
    public weak var delegate: HIDTransportDelegate?
    public var targetAddress: String?
    public var isPaused = false

    private static let connectTimeout: TimeInterval = 15
    /// When a link to the host already exists the host may be opening its own HID channels
    /// (e.g. the user clicked "Connect" on the iMac); opening ours at the same time collides.
    private static let hostGracePeriod: TimeInterval = 1.5
    private let log = Logger(subsystem: "btskey", category: "classic-hid")
    private let serviceName: String
    private let providerName: String

    private var serviceRecord: IOBluetoothSDPServiceRecord?
    private var publishRetry: DispatchWorkItem?
    private var publishAttempts = 0
    private static let publishRetryInterval: TimeInterval = 1
    private static let publishMaxAttempts = 30
    private var hasNotifiedConnect = false
    private var incomingNotifications: [IOBluetoothUserNotification] = []
    private var device: IOBluetoothDevice?
    private var controlChannel: IOBluetoothL2CAPChannel?
    private var interruptChannel: IOBluetoothL2CAPChannel?
    /// PSMs whose channel has finished opening (inbound channels arrive already open).
    private var openPSMs: Set<UInt16> = []
    private var isOutboundInFlight = false
    private var watchdog: DispatchWorkItem?
    private var graceWork: DispatchWorkItem?
    private var isResettingLink = false
    private var resetPoll: DispatchWorkItem?
    private var linkStatePoll: DispatchWorkItem?
    private static let resetPollInterval: TimeInterval = 0.25
    private static let resetMaxPolls = 20
    private var aclDisconnectNotification: IOBluetoothUserNotification?
    private var lastReports: [HIDReportID: [UInt8]] = [:]

    public init(serviceName: String = "BTS Key", providerName: String = "bts-key") {
        self.serviceName = serviceName
        self.providerName = providerName
    }

    public var isConnected: Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return openPSMs.isSuperset(of: [SDPRecordBuilder.controlPSM, SDPRecordBuilder.interruptPSM])
    }

    // MARK: - Public API (main thread)

    public func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        ensurePublished()
        guard incomingNotifications.isEmpty else { return }
        for psm in [SDPRecordBuilder.controlPSM, SDPRecordBuilder.interruptPSM] {
            if let note = IOBluetoothL2CAPChannel.register(
                forChannelOpenNotifications: self,
                selector: #selector(incomingChannelOpened(_:channel:)),
                withPSM: BluetoothL2CAPPSM(psm),
                direction: kIOBluetoothUserNotificationChannelDirectionIncoming
            ) {
                incomingNotifications.append(note)
            } else {
                log.error("could not listen for incoming PSM \(psm, privacy: .public)")
            }
        }
        log.notice("listening for host-initiated connections")
    }

    public func connect() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isConnected, !isOutboundInFlight else { return }
        guard let address = targetAddress else { return fail(.noTarget) }
        guard let device = IOBluetoothDevice(addressString: address) else { return fail(.invalidAddress(address)) }
        guard device.isPaired() else {
            let name = device.name.flatMap { $0.isEmpty ? nil : $0 } ?? address
            return fail(.notPaired(name))
        }
        // Without our record the host's connection lands in macOS' own HID host instead of here.
        if serviceRecord == nil, publishRetry == nil {
            // A new connection attempt refills an exhausted budget; the timer does the retrying.
            publishAttempts = 0
            ensurePublished()
        }
        guard serviceRecord != nil else { return fail(.notPublished) }

        closeChannels()
        self.device = device
        isOutboundInFlight = true
        watchBasebandLink(of: device)
        armWatchdog()
        log.notice("connecting to \(address, privacy: .public) (ACL up: \(device.isConnected(), privacy: .public))")
        if device.isConnected() {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isOutboundInFlight, self.controlChannel == nil else { return }
                // The host did not open its HID channels on the existing link. Channels opened on a
                // link we did not establish are closed by IOBluetooth within milliseconds (seen when
                // macOS' own HID host holds the link), so drop it and connect afresh.
                self.resetBasebandLinkThenConnect()
            }
            graceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hostGracePeriod, execute: work)
        } else {
            let status = device.openConnection(self)
            if status != kIOReturnSuccess { fail(.connectionFailed(code: status)) }
        }
    }

    public func disconnect() {
        dispatchPrecondition(condition: .onQueue(.main))
        let hadLink = controlChannel != nil || interruptChannel != nil || isOutboundInFlight
        closeChannels()
        if hadLink { delegate?.transportDidDisconnect(self, error: nil) }
    }

    public func shutdown() {
        dispatchPrecondition(condition: .onQueue(.main))
        closeChannels()
        publishRetry?.cancel()
        publishRetry = nil
        incomingNotifications.forEach { $0.unregister() }
        incomingNotifications = []
        serviceRecord?.remove()
        serviceRecord = nil
    }

    public func send(reportID: HIDReportID, payload: [UInt8]) {
        let body = { [self] in
            guard let channel = interruptChannel else { return }
            lastReports[reportID] = payload
            write(HIDPFrame.dataInput(reportID: reportID, payload: payload), to: channel)
        }
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }

    // MARK: - Publishing

    /// Publishes the SDP record, retrying in the background: the first attempt right after the
    /// Bluetooth permission prompt is answered fails, and an app without a record never gets
    /// the host's channels.
    @discardableResult
    private func ensurePublished() -> Bool {
        if serviceRecord != nil { return true }
        publishAttempts += 1
        let dictionary = SDPRecordBuilder(serviceName: serviceName, providerName: providerName).dictionary
        serviceRecord = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: dictionary)
        if serviceRecord != nil {
            log.notice("SDP record published (attempt \(self.publishAttempts, privacy: .public))")
            publishRetry?.cancel()
            publishRetry = nil
            return true
        }
        log.error("SDP publish failed (attempt \(self.publishAttempts, privacy: .public))")
        guard publishAttempts < Self.publishMaxAttempts, publishRetry == nil else { return false }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.publishRetry = nil
            self.ensurePublished()
        }
        publishRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.publishRetryInterval, execute: work)
        return false
    }

    // MARK: - Outbound

    /// IOBluetoothDevice async connection callback.
    @objc public func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        // Ignore a late callback from an attempt that was cancelled or replaced.
        guard isOutboundInFlight, let current = self.device,
              device?.addressString == current.addressString else { return }
        guard status == kIOReturnSuccess else { return fail(.connectionFailed(code: status)) }
        // isConnected() lags the completion; opening before it agrees makes IOBluetooth wait
        // synchronously on the main thread (seen as a 9 s stall), so poll briefly instead.
        waitForLinkState(remaining: Self.linkStatePolls)
    }

    private static let linkStatePollInterval: TimeInterval = 0.1
    private static let linkStatePolls = 30

    private func waitForLinkState(remaining: Int) {
        guard isOutboundInFlight, let device else { return }
        if device.isConnected() {
            openOutbound(psm: SDPRecordBuilder.controlPSM)
            return
        }
        guard remaining > 0 else { return fail(.linkClosed) }
        let work = DispatchWorkItem { [weak self] in self?.waitForLinkState(remaining: remaining - 1) }
        linkStatePoll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.linkStatePollInterval, execute: work)
    }

    private func openOutbound(psm: UInt16) {
        guard isOutboundInFlight, let device else { return }
        // Never ask for a channel without a live baseband link: IOBluetooth then re-pages the
        // host and waits for the channel *synchronously on the main thread*, freezing the app
        // for as long as the host stays silent. Seen in a sample of the app.
        guard device.isConnected() else { return fail(.linkClosed) }
        var channel: IOBluetoothL2CAPChannel?
        let status = device.openL2CAPChannelAsync(&channel, withPSM: BluetoothL2CAPPSM(psm), delegate: self)
        guard status == kIOReturnSuccess, let channel else {
            return fail(.channelOpenFailed(psm: psm, code: status))
        }
        adopt(channel)
    }

    // MARK: - Inbound

    @objc private func incomingChannelOpened(_ notification: IOBluetoothUserNotification, channel: IOBluetoothL2CAPChannel) {
        let address = channel.device?.addressString ?? "?"
        let isPaired = channel.device?.isPaired() ?? false
        guard InboundPolicy.shouldAccept(isPaired: isPaired, isPaused: isPaused) else {
            log.notice("refusing host-initiated PSM \(channel.psm, privacy: .public) from \(address, privacy: .public) (paired: \(isPaired, privacy: .public), paused: \(self.isPaused, privacy: .public))")
            channel.close()
            return
        }
        if isOutboundInFlight, !InboundPolicy.isSameHost(targetAddress, address) {
            // The user asked for a specific iMac; another bonded host must not hijack that attempt.
            log.notice("refusing PSM \(channel.psm, privacy: .public) from \(address, privacy: .public) while connecting to \(self.targetAddress ?? "?", privacy: .public)")
            channel.close()
            return
        }
        if let current = device, !InboundPolicy.isSameHost(current.addressString, address), channel.psm != SDPRecordBuilder.controlPSM {
            log.notice("refusing PSM \(channel.psm, privacy: .public) from \(address, privacy: .public): control channel came from another host")
            channel.close()
            return
        }
        guard !isConnected else {
            // A healthy link is never torn down by a stray open; a dead link reports l2capChannelClosed first.
            log.info("refusing extra PSM \(channel.psm, privacy: .public): link already up")
            channel.close()
            return
        }
        log.notice("host-initiated PSM \(channel.psm, privacy: .public) from \(address, privacy: .public)")
        if channel.psm == SDPRecordBuilder.controlPSM {
            // The host is (re)building the link: drop any half-open outbound attempt and follow its lead.
            closeChannels()
        }
        if isResettingLink {
            // The host came to us while we were dropping the stale link: follow the host instead.
            isResettingLink = false
            resetPoll?.cancel()
            resetPoll = nil
        }
        if device == nil, let host = channel.device {
            device = host
            watchBasebandLink(of: host)
        }
        if watchdog == nil { armWatchdog() }
        channel.setDelegate(self)
        adopt(channel)
        openPSMs.insert(UInt16(channel.psm))
        completeIfReady()
    }

    /// Fails fast when the baseband link drops instead of waiting for the watchdog.
    private func watchBasebandLink(of device: IOBluetoothDevice) {
        aclDisconnectNotification?.unregister()
        aclDisconnectNotification = device.register(forDisconnectNotification: self, selector: #selector(basebandDisconnected(_:device:)))
    }

    private func resetBasebandLinkThenConnect() {
        guard let device else { return }
        log.notice("existing baseband link has no HID channels; resetting it")
        isResettingLink = true
        let status = device.closeConnection()
        if status != kIOReturnSuccess { log.error("closeConnection failed: \(status, privacy: .public)") }
        pollForLinkDown(remaining: Self.resetMaxPolls)
    }

    private func pollForLinkDown(remaining: Int) {
        guard isResettingLink, isOutboundInFlight, let device else { return }
        if !device.isConnected() || remaining <= 0 {
            isResettingLink = false
            log.notice("reconnecting on a fresh baseband link")
            let status = device.openConnection(self)
            if status != kIOReturnSuccess { fail(.connectionFailed(code: status)) }
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.pollForLinkDown(remaining: remaining - 1) }
        resetPoll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resetPollInterval, execute: work)
    }

    @objc private func basebandDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Our own reset drops the link on purpose; the poll takes it from there.
        guard !isResettingLink else { return }
        guard InboundPolicy.isSameHost(device.addressString, self.device?.addressString),
              isOutboundInFlight || controlChannel != nil || interruptChannel != nil else { return }
        log.notice("baseband link to \(device.addressString ?? "?", privacy: .public) dropped")
        fail(.linkClosed)
    }

    // MARK: - Channel bookkeeping

    /// The role a delegate callback's channel plays, or nil if it is not ours (by PSM and host).
    private func role(of channel: IOBluetoothL2CAPChannel?) -> HIDChannelRole? {
        guard let channel, let role = HIDChannelRole(psm: UInt16(channel.psm)) else { return nil }
        let ours = role == .control ? controlChannel : interruptChannel
        guard ours != nil else { return nil }
        if let expected = device?.addressString, let actual = channel.device?.addressString,
           !InboundPolicy.isSameHost(expected, actual) { return nil }
        return role
    }

    private func adopt(_ channel: IOBluetoothL2CAPChannel) {
        let isControl = channel.psm == SDPRecordBuilder.controlPSM
        let previous = isControl ? controlChannel : interruptChannel
        if let previous, previous !== channel {
            openPSMs.remove(UInt16(previous.psm))
            log.notice("closing replaced PSM \(previous.psm, privacy: .public) channel")
            // Detach first: a late callback from the old channel must not be mistaken for the new one.
            previous.setDelegate(nil)
            previous.close()
        }
        if isControl { controlChannel = channel } else { interruptChannel = channel }
    }

    private func completeIfReady() {
        guard isConnected, !hasNotifiedConnect else { return }
        hasNotifiedConnect = true
        isOutboundInFlight = false
        watchdog?.cancel()
        watchdog = nil
        let address = device?.addressString ?? targetAddress ?? "?"
        let name = device?.name
        targetAddress = address
        log.notice("HID link up with \(address, privacy: .public)")
        delegate?.transportDidConnect(self, hostAddress: address, hostName: name)
    }

    private func armWatchdog() {
        watchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isConnected else { return }
            self.fail(.timedOut)
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout, execute: work)
    }

    private func fail(_ error: HIDTransportError) {
        log.error("link failed: \(error.localizedDescription, privacy: .public)")
        closeChannels()
        delegate?.transportDidDisconnect(self, error: error)
    }

    /// Closes channels but keeps the SDP record and the incoming listeners.
    private func closeChannels() {
        watchdog?.cancel()
        watchdog = nil
        graceWork?.cancel()
        graceWork = nil
        resetPoll?.cancel()
        resetPoll = nil
        linkStatePoll?.cancel()
        linkStatePoll = nil
        isResettingLink = false
        aclDisconnectNotification?.unregister()
        aclDisconnectNotification = nil
        isOutboundInFlight = false
        hasNotifiedConnect = false
        let channels = [interruptChannel, controlChannel]
        interruptChannel = nil
        controlChannel = nil
        openPSMs = []
        if channels.contains(where: { $0 != nil }) {
            log.notice("closeChannels closing \(channels.compactMap { $0?.psm }.map(String.init).joined(separator: ","), privacy: .public)")
        }
        channels.forEach {
            $0?.setDelegate(nil)
            $0?.close()
        }
        device = nil
        lastReports = [:]
    }

    // MARK: - Writing

    private func write(_ bytes: [UInt8], to channel: IOBluetoothL2CAPChannel) {
        // The buffer must outlive the asynchronous write; it is freed in l2capChannelWriteComplete.
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
        buffer.initialize(from: bytes, count: bytes.count)
        let status = channel.writeAsync(buffer, length: UInt16(bytes.count), refcon: buffer)
        if channel.psm == SDPRecordBuilder.controlPSM {
            log.notice("control -> \(bytes.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "), privacy: .public) status \(status, privacy: .public)")
        }
        if status != kIOReturnSuccess {
            buffer.deallocate()
            log.error("write failed on PSM \(channel.psm, privacy: .public): \(status, privacy: .public)")
        }
    }

    private func handleControlMessage(_ bytes: [UInt8], on channel: IOBluetoothL2CAPChannel) {
        log.notice("control <- \(bytes.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "), privacy: .public)")
        switch HIDPFrame.parse(bytes) {
        case .getReport(_, let reportID):
            let id = reportID.flatMap(HIDReportID.init(rawValue:)) ?? .keyboard
            let size = id == .keyboard ? KeyboardReport.byteCount : MouseReport.byteCount
            let payload = lastReports[id] ?? [UInt8](repeating: 0, count: size)
            write(HIDPFrame.dataInput(reportID: id, payload: payload), to: channel)
        case .setReport, .setProtocol:
            // LED state, Apple feature reports and protocol switches are acknowledged and otherwise ignored.
            write(HIDPFrame.handshake(.successful), to: channel)
        case .getProtocol:
            write([HIDPFrame.ProtocolMode.report.rawValue], to: channel)
        case .suspend, .exitSuspend, .dataOutput:
            break // One-way notifications: the profile expects no reply.
        case .virtualCableUnplug:
            log.notice("host sent virtual cable unplug")
            fail(.hostUnplugged)
        case .unknown:
            write(HIDPFrame.handshake(.unsupportedRequest), to: channel)
        }
    }
}

// MARK: - IOBluetoothL2CAPChannelDelegate (main thread)

extension ClassicHIDTransport: IOBluetoothL2CAPChannelDelegate {
    public func l2capChannelOpenComplete(_ channel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        guard role(of: channel) != nil else { return }
        let psm = UInt16(channel.psm)
        guard error == kIOReturnSuccess else {
            return fail(.channelOpenFailed(psm: psm, code: error))
        }
        openPSMs.insert(psm)
        if psm == SDPRecordBuilder.controlPSM, isOutboundInFlight, interruptChannel == nil {
            openOutbound(psm: SDPRecordBuilder.interruptPSM)
        }
        completeIfReady()
    }

    public func l2capChannelData(_ channel: IOBluetoothL2CAPChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard role(of: channel) == .control, let control = controlChannel else { return }
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        handleControlMessage(bytes, on: control)
    }

    public func l2capChannelWriteComplete(_ channel: IOBluetoothL2CAPChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        refcon?.assumingMemoryBound(to: UInt8.self).deallocate()
        if error != kIOReturnSuccess {
            log.error("async write failed on PSM \(channel.psm, privacy: .public): \(error, privacy: .public)")
        }
    }

    public func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel!) {
        guard role(of: channel) != nil else { return }
        log.notice("PSM \(channel.psm, privacy: .public) closed by host")
        fail(.linkClosed)
    }
}
