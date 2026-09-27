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
/// - Only outbound links work. When the host opens the channels itself, IOBluetooth
///   either never surfaces them to this process (idle) or surfaces channel objects that
///   never deliver data (while an outbound attempt is in flight), so the host's request
///   times out after 3 s either way. No channel or connect notifications are registered (see
///   `start()`); the host's baseband link is detected by polling and reported to the delegate
///   as a cue to connect outbound.
/// - Opening channels right after `connectionComplete` is safe; `isConnected()` can lag
///   or stay false for some pairing records and must not gate it.
///
/// IOBluetooth only works on the thread whose run loop services it (objects used
/// from another thread fail with kIOReturnError), so everything runs on main.
public final class ClassicHIDTransport: NSObject, HIDTransport {
    public weak var delegate: HIDTransportDelegate?
    public var targetAddress: String? {
        didSet { if targetAddress != oldValue { wasTargetLinkUp = false } }   // edge detector is per target
    }
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
    private var hostLinkPoll: Timer?
    private var wasTargetLinkUp = false
    private static let hostLinkPollInterval: TimeInterval = 2
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
        // Deliberately no IOBluetooth notification registrations here. Registering for connect
        // notifications makes this process' device objects report isConnected() == false forever
        // and every channel open fail (verified 2026-09-27); channel-open notifications never
        // deliver data. Host-initiated links are detected by polling the target instead.
        startHostLinkPoll()
        log.notice("publishing HID service; watching the target for host-initiated links")
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
        hostLinkPoll?.invalidate()
        hostLinkPoll = nil
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
        // A successful completion is the reliable "link up" signal: isConnected() lags it and
        // stays false altogether for some pairing records. Opening now was verified stall-free.
        openOutbound(psm: SDPRecordBuilder.controlPSM, linkKnownUp: true)
    }

    /// Host-initiated baseband link: the cue that the host wants its keyboard back. The target's
    /// isConnected() flips to true when the host pages us (it only lags for links *we* open).
    private func startHostLinkPoll() {
        guard hostLinkPoll == nil else { return }
        let timer = Timer(timeInterval: Self.hostLinkPollInterval, repeats: true) { [weak self] _ in self?.pollHostLink() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        hostLinkPoll = timer
    }

    private func pollHostLink() {
        guard let address = targetAddress, let target = IOBluetoothDevice(addressString: address) else { return }
        let isUp = target.isConnected()
        defer { wasTargetLinkUp = isUp }
        guard isUp, !wasTargetLinkUp, !isOutboundInFlight, !isConnected, !isPaused, target.isPaired() else { return }
        log.notice("host \(address, privacy: .public) brought up a link")
        delegate?.transportHostCameIntoRange(self, hostAddress: address, hostName: target.name)
    }

    private func openOutbound(psm: UInt16, linkKnownUp: Bool = false) {
        guard isOutboundInFlight, let device else { return }
        // Without a live baseband link IOBluetooth re-pages the host and waits synchronously on
        // the main thread. The connection-complete path is exempt (the link is up by definition).
        guard linkKnownUp || device.isConnected() else { return fail(.linkClosed) }
        var channel: IOBluetoothL2CAPChannel?
        let status = device.openL2CAPChannelAsync(&channel, withPSM: BluetoothL2CAPPSM(psm), delegate: self)
        guard status == kIOReturnSuccess, let channel else {
            return fail(.channelOpenFailed(psm: psm, code: status))
        }
        adopt(channel)
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
        let detectedRole = role(of: channel)
        log.debug("data \(dataLength, privacy: .public)B on PSM \(channel.psm, privacy: .public) from \(channel.device?.addressString ?? "?", privacy: .public) role=\(String(describing: detectedRole), privacy: .public)")
        guard detectedRole == .control, let control = controlChannel else { return }
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
