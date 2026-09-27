import AppKit
import IOBluetooth
import HIDCore
import ClassicHIDTransport
import InputCapture
import os

/// Glues the pure state machine to the transport, the event tap, the cursor lock and the HUD.
/// All state transitions happen on the main thread.
final class SessionController {
    var onStateChange: ((SessionState) -> Void)?
    /// Status item frame in screen coordinates, for placing the remote-mode box under it.
    var statusItemFrame: (() -> NSRect?)?
    var onError: ((String?) -> Void)?

    private(set) var machine = SessionStateMachine()
    private(set) var nextRetry: Date?
    private let settings: Settings
    private let transport: HIDTransport
    private let capture = EventTapCapture()
    private let cursorLock = CursorLock()
    private let hud = HUDWindow()
    private let overlay = RemoteStatusOverlay()
    private let powerSaver = PowerSaver()
    private let inputSources = InputSourceKeeper()
    private let log = Logger(subsystem: "btskey", category: "session")
    /// Starts at 4 s: a host that just dropped the link often reconnects by itself (or the user clicks
    /// "Connect" on the iMac), and an immediate outbound attempt from here collides with it.
    /// Capped at 10 s so a sleeping iMac is picked up soon after it wakes to its lock screen.
    private var reconnectPolicy = ReconnectPolicy.unattended
    let pairing = PairedDeviceWatcher()
    /// True after the unattended retry budget is spent; the app then only listens for the host.
    private(set) var isWaitingForHost = false
    private var reconnectWork: DispatchWorkItem?
    private var resumePolicy = RemoteResumePolicy()
    private var hostCueWork: DispatchWorkItem?

    var state: SessionState { machine.state }

    init(settings: Settings, transport: HIDTransport) {
        self.settings = settings
        self.transport = transport
        transport.delegate = self
        applySettings()
        wireCapture()
        observeSystemEvents()
        wirePairingWatcher()
    }

    /// The standard "move to another iMac" flow: pair it in Bluetooth settings, and the app
    /// adopts it as the target and connects when no link is up. A forgotten pairing stops
    /// every retry at once, even mid-backoff.
    private func wirePairingWatcher() {
        pairing.onAdded = { [weak self] computer in
            guard let self else { return }
            let isBusy = self.state == .connectedLocal || self.state == .connectedRemote || self.state == .connecting
            var hosts = self.settings.knownHosts
            hosts.record(address: computer.address, name: computer.name, kind: computer.kind, at: Date().timeIntervalSince1970)
            self.settings.knownHosts = hosts
            guard !isBusy else {
                self.onError?("새로 페어링된 \(computer.name)이(가) 기기 목록에 추가되었습니다.")
                return
            }
            self.log.notice("adopting newly paired host \(computer.address, privacy: .public)")
            self.hud.show(.pairedNewHost(computer.name))
            self.connect(toAddress: computer.address, name: computer.name)
        }
        pairing.onNamesChanged = { [weak self] in self?.refreshKnownHostNames() }
        pairing.onRemoved = { [weak self] address in
            guard let self else { return }
            var hosts = self.settings.knownHosts
            hosts.forget(address: address)
            self.settings.knownHosts = hosts
            guard InboundPolicy.isSameHost(self.settings.targetAddress, address) else { return }
            self.log.notice("target pairing removed; stopping")
            self.disconnect()
            self.settings.targetAddress = nil
            self.settings.targetName = nil
            self.transport.targetAddress = nil
            self.onError?("iMac 페어링이 해제되어 연결을 멈췄습니다. 다른 iMac을 페어링하거나 목록에서 선택하세요.")
        }
    }

    /// A freshly paired Mac is listed under a placeholder until its first connection; pick up the real name.
    private func refreshKnownHostNames() {
        var hosts = settings.knownHosts
        var changed = false
        for host in hosts.entries {
            guard let name = pairing.resolvedName(of: host.address), name != host.name else { continue }
            hosts.record(address: host.address, name: name, kind: host.kind, at: host.lastConnected)
            changed = true
            if InboundPolicy.isSameHost(settings.targetAddress, host.address) { settings.targetName = name }
        }
        if changed {
            settings.knownHosts = hosts
            onStateChange?(machine.state)
        }
    }

    /// Explicit user request after the unattended budget was spent.
    func retryNow() {
        guard settings.targetAddress != nil else { return }
        reconnectPolicy.reset()
        settings.wantsConnection = true
        settings.isPaused = false
        transport.isPaused = false
        attemptConnection()
    }

    private var hasStarted = false

    /// Publishes the HID service, listens for the iMac, and resumes the last intent. Idempotent:
    /// the first-run guide defers this until the user reaches the Bluetooth permission step, because
    /// the first IOBluetooth call raises the system prompt and blocks until it is answered.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        transport.targetAddress = settings.targetAddress
        transport.isPaused = settings.isPaused
        transport.start()
        pairing.start()
        if let target = settings.targetAddress, pairing.isPaired(address: target) == false {
            // The user forgot this iMac while the app was not running (nil = list unavailable, keep it).
            settings.wantsConnection = false
            settings.targetAddress = nil
            settings.targetName = nil
            transport.targetAddress = nil
        }
        if settings.wantsConnection, settings.targetAddress != nil {
            connect()
        }
    }

    func applySettings() {
        capture.pointerScaler = PointerScaler(multiplier: settings.pointerMultiplier)
        capture.hotkey = settings.hotkey
        capture.capsLockMapping = settings.capsLockMapping
    }

    func targetDidChange() {
        hostCueWork?.cancel()
        transport.targetAddress = settings.targetAddress
        if state != .idle {
            disconnect()
        }
    }

    /// Selects `address` as the target and connects to it (menu device rows, onboarding).
    func connect(toAddress address: String, name: String) {
        if !InboundPolicy.isSameHost(settings.targetAddress, address) {
            settings.targetAddress = address
            settings.targetName = name
            targetDidChange()
        }
        connect()
    }

    private func rememberHost(address: String, name: String?) {
        let device = IOBluetoothDevice(addressString: address)
        let kind = device.map { BluetoothDeviceKind(classOfDevice: $0.classOfDevice) } ?? .computer
        let displayName = PairedDeviceWatcher.resolvedName(name) ?? PairedDeviceWatcher.resolvedName(device?.name)
            ?? PairedDeviceWatcher.placeholderName(for: InboundPolicy.normalize(address))
        var hosts = settings.knownHosts
        hosts.record(address: address, name: displayName, kind: kind, at: Date().timeIntervalSince1970)
        settings.knownHosts = hosts
    }

    // MARK: - Commands

    func connect() {
        guard settings.targetAddress != nil else {
            onError?(HIDTransportError.noTarget.localizedDescription)
            return
        }
        guard startCapture() else { return }
        settings.wantsConnection = true
        settings.isPaused = false
        transport.isPaused = false
        reconnectPolicy.reset()
        attemptConnection()
    }

    func disconnect() {
        resumePolicy.clear()
        hostCueWork?.cancel()
        settings.wantsConnection = false
        settings.isPaused = true
        transport.isPaused = true
        cancelRetry()
        dispatch(.stopRequested)
        transport.disconnect()
        capture.stop()
    }

    func toggle() {
        // Remote mode is only safe while the event tap runs: it is the only way back to local input.
        guard capture.isRunning || machine.isCapturing else { return }
        resumePolicy.clear()
        dispatch(.toggleRequested)
    }

    var isLinkUp: Bool { state == .connectedLocal || state == .connectedRemote }

    func prepareForTermination() {
        pairing.stop()
        hostCueWork?.cancel()
        dispatch(.appWillTerminate)
        transport.shutdown()
        capture.stop()
    }

    // MARK: - Connection plumbing

    private func startCapture() -> Bool {
        guard InputPermissions.allGranted else {
            InputPermissions.request()
            onError?("손쉬운 사용과 입력 모니터링 권한을 허용한 뒤 다시 연결하세요.")
            return false
        }
        do {
            try capture.start()
            return true
        } catch {
            onError?(error.localizedDescription)
            return false
        }
    }

    private func attemptConnection() {
        cancelRetry()
        isWaitingForHost = false
        onError?(nil)
        dispatch(.connectRequested)
        transport.connect()
    }

    private func scheduleRetry() {
        guard settings.wantsConnection else { return }
        reconnectWork?.cancel()
        guard let delay = reconnectPolicy.nextDelayIfAllowed() else {
            // Stop paging a host that keeps refusing; it will connect to us when it wants a keyboard.
            isWaitingForHost = true
            nextRetry = nil
            log.notice("automatic retries exhausted; waiting for the host or the user")
            onError?("자동 재시도를 멈췄습니다. iMac 쪽에서 연결하거나 메뉴에서 다시 연결하세요.")
            onStateChange?(machine.state)
            return
        }
        isWaitingForHost = false
        nextRetry = Date().addingTimeInterval(delay)
        log.info("retry #\(self.reconnectPolicy.attempt, privacy: .public) in \(delay, privacy: .public)s")
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.settings.wantsConnection, !self.transport.isConnected else { return }
            self.attemptConnection()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        onStateChange?(machine.state)
    }

    private func cancelRetry() {
        reconnectWork?.cancel()
        reconnectWork = nil
        nextRetry = nil
    }

    // MARK: - State machine plumbing

    private func dispatch(_ event: SessionEvent) {
        let wasCapturing = machine.isCapturing
        let effects = machine.handle(event)
        capture.isCapturing = machine.isCapturing
        for effect in effects { perform(effect) }
        if machine.isCapturing != wasCapturing {
            machine.isCapturing ? enterRemoteMode() : leaveRemoteMode()
        }
        onStateChange?(machine.state)
    }

    private func enterRemoteMode() {
        inputSources.save()
        overlay.show(hotkey: settings.hotkey.displayString, anchor: statusItemFrame?())
        powerSaver.enter(settings.powerSaveMode)
    }

    private func leaveRemoteMode() {
        powerSaver.exit()
        overlay.hide()
        inputSources.restore()
    }

    var isPowerSaveAvailable: Bool { powerSaver.isAvailable }

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .sendAllUp:
            capture.releaseAll()
            transport.send(reportID: .mouse, payload: MouseReport().bytes)
        case .lockCursor:
            cursorLock.lock()
        case .unlockCursor:
            cursorLock.unlock()
        case .showHUD(let message):
            hud.show(message)
        }
    }

    private func wireCapture() {
        capture.onKeyboardReport = { [transport] report in
            transport.send(reportID: .keyboard, payload: report.bytes)
        }
        capture.onMouseReport = { [transport] report in
            transport.send(reportID: .mouse, payload: report.bytes)
        }
        capture.onHotkey = { [weak self] in
            DispatchQueue.main.async { self?.toggle() }
        }
        capture.onPointerMotion = { [cursorLock] in cursorLock.pin() }
        capture.onTapDisabled = { [log] in
            log.warning("event tap was disabled by the system and re-enabled")
        }
    }

    private func observeSystemEvents() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.dispatch(.screenLocked)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.dispatch(.screenLocked)
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // The backoff may have grown while asleep; try right away after wake.
            guard let self, self.settings.wantsConnection, !self.transport.isConnected else { return }
            self.reconnectPolicy.reset()
            self.attemptConnection()
        }
    }
}

extension SessionController: HIDTransportDelegate {
    /// The host's own HID attempt dies after 3 s; connect outbound right after that window.
    private static let hostAttemptWindow: TimeInterval = 4

    func transportHostCameIntoRange(_ transport: HIDTransport, hostAddress: String, hostName: String?) {
        guard !settings.isPaused else { return }
        let isTarget = InboundPolicy.isSameHost(settings.targetAddress, hostAddress)
        let isKnown = settings.knownHosts.contains(address: hostAddress)
        guard isTarget || isKnown || settings.targetAddress == nil else { return }
        guard !isLinkUp, state != .connecting else { return }
        log.notice("host \(hostAddress, privacy: .public) in range; connecting in \(Self.hostAttemptWindow, privacy: .public)s")
        hostCueWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isLinkUp, self.state != .connecting, !self.settings.isPaused else { return }
            let name = PairedDeviceWatcher.resolvedName(hostName) ?? self.settings.knownHosts.entries.first { InboundPolicy.isSameHost($0.address, hostAddress) }?.name ?? hostAddress
            self.reconnectPolicy.reset()
            self.connect(toAddress: hostAddress, name: name)
        }
        hostCueWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hostAttemptWindow, execute: work)
    }

    func transportDidConnect(_ transport: HIDTransport, hostAddress: String, hostName: String?) {
        if !InboundPolicy.isSameHost(settings.targetAddress, hostAddress) {
            // The user moved to another iMac and connected from there: follow it.
            log.notice("target host changed to \(hostAddress, privacy: .public)")
            settings.targetAddress = hostAddress
            settings.targetName = hostName ?? hostAddress
        }
        settings.wantsConnection = true
        rememberHost(address: hostAddress, name: hostName)
        hostCueWork?.cancel()
        cancelRetry()
        isWaitingForHost = false
        reconnectPolicy.reset()
        onError?(nil)
        // Keep the link even without permissions: dropping it looks like "connects then disconnects" on the iMac.
        // toggle() refuses remote mode until the event tap runs, so local input can never be stranded.
        if !capture.isRunning { _ = startCapture() }
        dispatch(.transportConnected)
        if settings.autoResumeRemote, capture.isRunning, resumePolicy.shouldResume(at: Date().timeIntervalSince1970) {
            // The iMac came back (wake, login screen) while the user was typing on it: hand input straight back.
            log.notice("resuming remote mode after reconnect")
            dispatch(.toggleRequested)
        }
    }

    func transportDidDisconnect(_ transport: HIDTransport, error: HIDTransportError?) {
        resumePolicy.linkDropped(wasCapturing: machine.isCapturing && error != nil, at: Date().timeIntervalSince1970)
        dispatch(.transportDisconnected)
        guard let error else { return }
        onError?(error.localizedDescription)
        if error.isRetryable {
            scheduleRetry()
        } else {
            settings.wantsConnection = false
            cancelRetry()
            dispatch(.stopRequested)
        }
    }
}
