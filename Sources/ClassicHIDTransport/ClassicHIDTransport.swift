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
///   `start()`). A link the host brought up shows only when it drops, through a disconnect
///   notification on the target, which is reported to the delegate as a cue to connect outbound.
/// - Opening channels right after `connectionComplete` is safe; `isConnected()` can lag
///   or stay false for some pairing records and must not gate it.
///
/// IOBluetooth only works on the thread whose run loop services it (objects used
/// from another thread fail with kIOReturnError), so everything runs on main.
public final class ClassicHIDTransport: NSObject, HIDTransport {
    public weak var delegate: HIDTransportDelegate?
    public var targetAddress: String? {
        didSet { if targetAddress != oldValue, hasStarted { watchTargetForHostLinks() } }
    }
    public var isPaused = false

    private static let connectTimeout: TimeInterval = 15
    /// When a link to the host already exists the host may be opening its own HID channels
    /// (e.g. the user clicked "Connect" on the iMac); opening ours at the same time collides.
    private static let hostGracePeriod: TimeInterval = 1.5
    /// Time between the baseband link coming up and the first channel request. Right after the
    /// link is up the stacks on both sides are still busy with it (service discovery, feature
    /// exchange); a channel requested in that window needs encryption started at once, and a
    /// freshly paired iMac left that request unanswered until the link timed out (5.5 s,
    /// status 708). After 1.5 s encryption starts in 23 ms (measured 2026-09-29).
    private static let linkSettleDelay: TimeInterval = 1.5
    private var settleWork: DispatchWorkItem?
    private let log = Logger(subsystem: "btskey", category: "classic-hid")
    private let serviceName: String
    private let providerName: String

    private var serviceRecord: IOBluetoothSDPServiceRecord?
    private var publishRetry: DispatchWorkItem?
    private var publishAttempts = 0
    private static let publishRetryInterval: TimeInterval = 1
    private static let publishMaxAttempts = 30
    private var hasNotifiedConnect = false
    private var hasStarted = false
    private var hostLinkWatch: IOBluetoothUserNotification?
    private var watchedTarget: IOBluetoothDevice?
    private var hostLinkDrops = HostLinkDropFilter()
    private var device: IOBluetoothDevice?
    private var controlChannel: IOBluetoothL2CAPChannel?
    private var interruptChannel: IOBluetoothL2CAPChannel?
    /// PSMs whose channel has finished opening (inbound channels arrive already open).
    private var openPSMs: Set<UInt16> = []
    private var isOutboundInFlight = false
    /// True once the baseband link of the current attempt is known to be up. A disconnect
    /// notification that arrives before that belongs to the previous link.
    private var isLinkEstablished = false
    private var attemptStartedAt = Date()
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
        // deliver data, with or without a PSM filter. Host-initiated links are noticed when they
        // drop (see watchTargetForHostLinks).
        hasStarted = true
        watchTargetForHostLinks()
        log.notice("publishing HID service")
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
        attemptStartedAt = Date()
        watchBasebandLink(of: device)
        armWatchdog()
        let isLinkUp = device.isConnected()
        isLinkEstablished = isLinkUp
        log.notice("connecting to \(address, privacy: .public) (ACL up: \(isLinkUp, privacy: .public))")
        if isLinkUp {
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
            log.notice("step \(self.elapsed, privacy: .public): baseband link requested (status \(status, privacy: .public))")
            if status != kIOReturnSuccess { fail(.connectionFailed(code: status)) }
        }
    }

    /// Seconds since the current attempt began, for reading the steps of an attempt in the log.
    private var elapsed: String {
        String(format: "+%.2fs", Date().timeIntervalSince(attemptStartedAt))
    }

    public func disconnect() {
        dispatchPrecondition(condition: .onQueue(.main))
        let hadLink = controlChannel != nil || interruptChannel != nil || isOutboundInFlight
        let host = device
        closeChannels()
        if hadLink {
            releaseBasebandLink(of: host)
            delegate?.transportDidDisconnect(self, error: nil)
        }
    }

    public func shutdown() {
        dispatchPrecondition(condition: .onQueue(.main))
        let host = device
        closeChannels()
        releaseBasebandLink(of: host)
        publishRetry?.cancel()
        publishRetry = nil
        hostLinkWatch?.unregister()
        hostLinkWatch = nil
        watchedTarget = nil
        serviceRecord?.remove()
        serviceRecord = nil
    }

    /// Reports handed to the interrupt channel and writes the stack confirmed, for diagnostics.
    public private(set) var writesRequested = 0
    public private(set) var writesCompleted = 0

    public func send(reportID: HIDReportID, payload: [UInt8]) {
        let body = { [self] in
            guard let channel = interruptChannel else {
                log.error("report \(reportID.rawValue, privacy: .public) dropped: no interrupt channel")
                return
            }
            writesRequested += 1
            // Input source keys only (🌐 byte, Caps Lock); typing is not logged.
            let isInputSourceKey = reportID == .keyboard
                && (payload.last == 1 || payload.dropFirst(2).dropLast().contains(0x39))
            if isInputSourceKey {
                log.info("radio: report \(reportID.rawValue, privacy: .public) [\(payload.map { String(format: "%02x", $0) }.joined(separator: " "), privacy: .public)] queued (writes requested \(self.writesRequested, privacy: .public), confirmed \(self.writesCompleted, privacy: .public))")
            }
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
              device?.addressString == current.addressString else {
            log.notice("late baseband completion ignored (status \(status, privacy: .public))")
            return
        }
        log.notice("step \(self.elapsed, privacy: .public): baseband link complete (status \(status, privacy: .public))")
        guard status == kIOReturnSuccess else { return fail(.connectionFailed(code: status)) }
        isLinkEstablished = true
        // A successful completion is the reliable "link up" signal: isConnected() lags it and
        // stays false altogether for some pairing records.
        // A second completion for the same host must not open a second control channel.
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.openOutbound(psm: SDPRecordBuilder.controlPSM, linkKnownUp: true)
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.linkSettleDelay, execute: work)
    }

    /// Watches the target for links the host brings up. The watch is a disconnect notification
    /// on a device object held for as long as the target stays the same: it is the only signal
    /// macOS gives this process about such a link, and it comes when the link drops.
    private func watchTargetForHostLinks() {
        hostLinkWatch?.unregister()
        hostLinkWatch = nil
        watchedTarget = nil
        guard let address = targetAddress, let target = IOBluetoothDevice(addressString: address) else { return }
        watchedTarget = target
        hostLinkWatch = target.register(forDisconnectNotification: self, selector: #selector(targetLinkDropped(_:device:)))
        log.notice("watching \(address, privacy: .public) for links the host brings up (registered: \(self.hostLinkWatch != nil, privacy: .public))")
    }

    @objc private func targetLinkDropped(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // While an attempt or a link of ours exists, its own watcher deals with the drop.
        guard !isOutboundInFlight, controlChannel == nil, interruptChannel == nil else { return }
        guard hostLinkDrops.isHostLinkDrop(at: Date().timeIntervalSince1970) else {
            log.info("link drop after releasing our own link; not a cue")
            return
        }
        guard !isPaused, device.isPaired(), let address = targetAddress else { return }
        log.notice("a link the host \(address, privacy: .public) brought up has dropped; it asked for its keyboard")
        delegate?.transportHostCameIntoRange(self, hostAddress: address, hostName: device.name)
    }

    private func openOutbound(psm: UInt16, linkKnownUp: Bool = false) {
        guard isOutboundInFlight, let device else { return }
        // Without a live baseband link IOBluetooth re-pages the host and waits synchronously on
        // the main thread. The connection-complete path is exempt (the link is up by definition).
        guard linkKnownUp || device.isConnected() else { return fail(.linkClosed) }
        var channel: IOBluetoothL2CAPChannel?
        let status = device.openL2CAPChannelAsync(&channel, withPSM: BluetoothL2CAPPSM(psm), delegate: self)
        log.notice("step \(self.elapsed, privacy: .public): channel 0x\(String(psm, radix: 16), privacy: .public) requested (status \(status, privacy: .public))")
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
            isLinkEstablished = false
            log.notice("step \(self.elapsed, privacy: .public): reconnecting on a fresh baseband link")
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
        // The notification for the previous link can arrive seconds late, after the next attempt
        // began; it killed attempts whose own link was still coming up.
        guard isLinkEstablished else {
            log.notice("step \(self.elapsed, privacy: .public): disconnect notification for an earlier link ignored")
            return
        }
        log.notice("step \(self.elapsed, privacy: .public): baseband link to \(device.addressString ?? "?", privacy: .public) dropped")
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
        log.notice("step \(self.elapsed, privacy: .public): HID link up with \(address, privacy: .public)")
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
        log.error("step \(self.elapsed, privacy: .public): link failed: \(error.localizedDescription, privacy: .public)")
        let host = device
        closeChannels()
        releaseBasebandLink(of: host)
        delegate?.transportDidDisconnect(self, error: error)
    }

    /// Drops the baseband link after the HID channels are gone. Left alone it lingers for about
    /// 15 s: both Bluetooth settings keep saying "connected" although no keyboard is served, and
    /// the next attempt starts on a link that is about to disappear under it.
    private func releaseBasebandLink(of host: IOBluetoothDevice?) {
        guard let host else { return }
        hostLinkDrops.expectOwnDrop(at: Date().timeIntervalSince1970)
        let started = Date()
        let status = host.closeConnection()
        log.notice("baseband link released (status \(status, privacy: .public), \(String(format: "%.2f", Date().timeIntervalSince(started)), privacy: .public)s)")
    }

    /// Closes channels but keeps the SDP record and the incoming listeners.
    private func closeChannels() {
        watchdog?.cancel()
        watchdog = nil
        graceWork?.cancel()
        graceWork = nil
        settleWork?.cancel()
        settleWork = nil
        resetPoll?.cancel()
        resetPoll = nil
        isResettingLink = false
        aclDisconnectNotification?.unregister()
        aclDisconnectNotification = nil
        isOutboundInFlight = false
        isLinkEstablished = false
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
        log.notice("step \(self.elapsed, privacy: .public): channel 0x\(String(psm, radix: 16), privacy: .public) open complete (status \(error, privacy: .public))")
        guard error == kIOReturnSuccess else {
            return fail(.channelOpenFailed(psm: psm, code: error))
        }
        // An open channel proves the link, however it came up.
        isLinkEstablished = true
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
        writesCompleted += 1
        if error != kIOReturnSuccess {
            log.error("async write failed on PSM \(channel.psm, privacy: .public): \(error, privacy: .public)")
        }
    }

    public func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel!) {
        guard role(of: channel) != nil else { return }
        // Channels that close while the link stays up were closed by the host on purpose; when
        // the link is gone (or its state is unknown) this is treated as a lost link.
        let isLinkStillUp = hasNotifiedConnect && (device?.isConnected() ?? false)
        log.notice("PSM \(channel.psm, privacy: .public) closed by host (link still up: \(isLinkStillUp, privacy: .public))")
        fail(isLinkStillUp ? .hostClosed : .linkClosed)
    }
}
