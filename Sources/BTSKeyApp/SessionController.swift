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
    /// One retry, 4 s later: a host that just dropped the link often reconnects by itself (or the
    /// user clicks "Connect" on the iMac), and an immediate outbound attempt collides with it.
    private var reconnectPolicy = ReconnectPolicy.unattended
    /// Keeps a host that pages this Mac over and over from restarting the attempts each time.
    private var hostCuePolicy = HostCuePolicy()
    let pairing: PairedDeviceWatcher
    /// True after the unattended attempts are spent; only the user starts the next one.
    private(set) var isWaitingForUser = false
    private var reconnectWork: DispatchWorkItem?
    private var resumePolicy = RemoteResumePolicy()
    private var hostCueWork: DispatchWorkItem?

    var state: SessionState { machine.state }

    init(settings: Settings, transport: HIDTransport) {
        self.settings = settings
        self.transport = transport
        pairing = PairedDeviceWatcher(settings: settings)
        transport.delegate = self
        applySettings()
        wireCapture()
        observeSystemEvents()
        wirePairingWatcher()
    }

    /// The standard "move to another iMac" flow: pair it in Bluetooth settings, and the app
    /// adopts it as the target and connects unless a link is in use. A forgotten pairing stops
    /// every retry at once, even mid-backoff.
    private func wirePairingWatcher() {
        pairing.onAdded = { [weak self] computers in self?.adopt(newlyPaired: computers) }
        pairing.onNamesChanged = { [weak self] in self?.refreshKnownHostNames() }
        pairing.onRemoved = { [weak self] address in
            guard let self else { return }
            var hosts = self.settings.knownHosts
            hosts.forget(address: address)
            self.settings.knownHosts = hosts
            // The Caps Lock choice for this host is kept: pairing the same iMac again is common
            // (a changed descriptor needs it) and the choice is about the iMac, not the pairing.
            guard InboundPolicy.isSameHost(self.settings.targetAddress, address) else { return }
            self.log.notice("target pairing removed; stopping")
            self.disconnect()
            self.settings.targetAddress = nil
            self.settings.targetName = nil
            self.transport.targetAddress = nil
            self.onError?("iMac 페어링이 해제되어 연결을 멈췄습니다. 다른 iMac을 페어링하거나 목록에서 선택하세요.")
        }
    }

    private func adopt(newlyPaired computers: [PairedDeviceWatcher.PairedComputer]) {
        var hosts = settings.knownHosts
        // A host that was served before keeps its history; pairing again makes it "repaired".
        for computer in computers where !hosts.contains(address: computer.address) {
            hosts.record(address: computer.address, name: computer.name, kind: computer.kind, at: KnownHost.neverServed)
        }
        settings.knownHosts = hosts
        guard computers.count == 1, let computer = computers.first else {
            log.notice("\(computers.count, privacy: .public) hosts paired at once; leaving the choice to the user")
            onError?("새로 페어링된 컴퓨터가 \(computers.count)대입니다. 메뉴에서 연결할 기기를 선택하세요.")
            return
        }
        guard !isLinkUp else {
            onError?("새로 페어링된 \(computer.name)이(가) 기기 목록에 추가되었습니다.")
            return
        }
        let familiarity = pairing.familiarity(of: computer.address)
        log.notice("adopting newly paired host \(computer.address, privacy: .public) (\(String(describing: familiarity), privacy: .public))")
        showHUD(.pairedNewHost(computer.name))
        connect(toAddress: computer.address, name: computer.name)
    }

    /// How far up the stack the link to the target reaches, for telling "Bluetooth says
    /// connected" apart from "the keyboard works".
    var linkLayerStatus: LinkLayerStatus {
        guard let address = settings.targetAddress, let device = IOBluetoothDevice(addressString: address) else { return .notPaired }
        return LinkLayerStatus(isPaired: device.isPaired(), isBasebandUp: device.isConnected(), areHIDChannelsOpen: transport.isConnected)
    }

    var targetFamiliarity: HostFamiliarity? {
        settings.targetAddress.map { pairing.familiarity(of: $0) }
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
        hostCuePolicy.reset()
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
        if let target = settings.targetAddress, !pairing.isPaired(address: target) {
            // The user forgot this iMac while the app was not running.
            log.notice("saved target \(target, privacy: .public) is no longer paired; cleared")
            settings.wantsConnection = false
            settings.targetAddress = nil
            settings.targetName = nil
            transport.targetAddress = nil
        }
        // The saved intent is resumed only after the first pairing list: a host paired while the
        // app was not running is adopted first, so the previous iMac is not paged for nothing.
        pairing.onFirstList = { [weak self] in
            guard let self else { return }
            self.logInventory()
            if self.settings.wantsConnection, self.settings.targetAddress != nil, self.state == .idle {
                self.connect()
            }
        }
        pairing.start()
    }

    /// One line per paired computer at launch, so a log shows what the app knew before it acted.
    private func logInventory() {
        log.notice("permissions granted: \(InputPermissions.allGranted, privacy: .public); target: \(self.settings.targetAddress ?? "none", privacy: .public); wantsConnection: \(self.settings.wantsConnection, privacy: .public); capsLock: \(self.settings.capsLockMapping.rawValue, privacy: .public)")
        for computer in pairing.pairedComputers() {
            let familiarity = pairing.familiarity(of: computer.address)
            log.notice("paired: \(computer.name, privacy: .public) (\(computer.address, privacy: .public)) \(String(describing: familiarity), privacy: .public)")
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
        applySettings()   // Caps Lock is chosen per host
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

    /// Connects because the user asked for it (menu, pairing a new iMac, launch with a saved
    /// intent): the unattended budgets start over.
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
        hostCuePolicy.reset()
        attemptConnection()
    }

    /// Connects because the host paged this Mac. The retry budget is left as it is, so a cue that
    /// arrives after the retries were spent gets this one attempt and no more.
    private func connectAfterHostCue() {
        guard settings.targetAddress != nil, startCapture() else { return }
        settings.wantsConnection = true
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
        hud.dismiss()
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
        isWaitingForUser = false
        onError?(nil)
        let familiarity = targetFamiliarity.map { String(describing: $0) } ?? "-"
        log.notice("attempt: target \(self.settings.targetAddress ?? "-", privacy: .public) familiarity=\(familiarity, privacy: .public) layer=\(String(describing: self.linkLayerStatus), privacy: .public) retriesUsed=\(self.reconnectPolicy.attempt, privacy: .public) cuesUsed=\(self.hostCuePolicy.used, privacy: .public)")
        dispatch(.connectRequested)
        // Connecting takes four to five seconds; without this the user sees nothing until it ends.
        showHUD(.connecting(isFirstConnection: targetFamiliarity?.isFirstConnection ?? true))
        transport.connect()
    }

    private func scheduleRetry() {
        guard settings.wantsConnection else { return }
        reconnectWork?.cancel()
        guard let delay = reconnectPolicy.nextDelayIfAllowed() else {
            // Stop paging a host that keeps refusing: every attempt keeps this Mac's radio busy.
            isWaitingForUser = true
            nextRetry = nil
            let layer = linkLayerStatus
            log.notice("automatic retry spent; waiting for the user (layer=\(String(describing: layer), privacy: .public))")
            let hint = layer == .basebandOnly
                ? "블루투스는 연결되어 있지만 키보드 채널이 열리지 않았습니다. iMac의 Bluetooth 설정에서 이 Mac을 ‘연결 해제’한 뒤 다시 시도하세요.\n"
                : ""
            onError?(hint + "자동 재시도를 멈췄습니다. 메뉴의 ‘지금 다시 연결’을 누르면 다시 시도합니다.")
            showHUD(.disconnected(.waitingForUser))
            onStateChange?(machine.state)
            return
        }
        isWaitingForUser = false
        nextRetry = Date().addingTimeInterval(delay)
        log.info("retry #\(self.reconnectPolicy.attempt, privacy: .public) in \(delay, privacy: .public)s")
        showHUD(.disconnected(.retrying(seconds: Int(delay.rounded()))))
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
            showHUD(message)
        }
    }

    private func showHUD(_ message: HUDMessage) {
        let context = HUDContext(hostName: settings.targetName, hotkey: settings.hotkey.displayString)
        hud.show(HUDPresentation(message, context: context))
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
    /// The cue arrives when the host's link has already dropped, so nothing is left to collide
    /// with; the short wait only lets the stack finish tearing that link down.
    private static let hostAttemptWindow: TimeInterval = 1

    func transportHostCameIntoRange(_ transport: HIDTransport, hostAddress: String, hostName: String?) {
        // Without a standing request from the user a paging host is not a reason to connect.
        guard settings.wantsConnection, !settings.isPaused,
              InboundPolicy.isSameHost(settings.targetAddress, hostAddress) else { return }
        guard !isLinkUp, state != .connecting, reconnectWork == nil else { return }
        guard hostCuePolicy.shouldHonorCue() else {
            log.notice("host \(hostAddress, privacy: .public) paged again; ignored until the user asks")
            return
        }
        log.notice("host \(hostAddress, privacy: .public) in range; connecting in \(Self.hostAttemptWindow, privacy: .public)s")
        hostCueWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isLinkUp, self.state != .connecting, !self.settings.isPaused,
                  InboundPolicy.isSameHost(self.settings.targetAddress, hostAddress) else { return }
            self.connectAfterHostCue()
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
            applySettings()
        }
        settings.wantsConnection = true
        rememberHost(address: hostAddress, name: hostName)
        hostCueWork?.cancel()
        cancelRetry()
        isWaitingForUser = false
        reconnectPolicy.reset()
        hostCuePolicy.reset()
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
        if error == .hostClosed {
            // The host disconnected on purpose: no attempt until the user asks or the host pages.
            cancelRetry()
            isWaitingForUser = true
            log.notice("host closed the link on purpose; waiting for the user")
            onError?(error.localizedDescription + " 다시 쓰려면 메뉴의 ‘지금 다시 연결’을 누르세요.")
            showHUD(.disconnected(.hostClosed))
            onStateChange?(machine.state)
        } else if error.isRetryable {
            scheduleRetry()
        } else {
            settings.wantsConnection = false
            cancelRetry()
            dispatch(.stopRequested)
        }
    }
}
