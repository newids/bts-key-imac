import AppKit
import HIDCore
import InputCapture

/// Menu bar item: three-state icon, device rows, commands, settings, help.
final class StatusMenuController: NSObject, NSMenuDelegate {
    /// Opens the guide at the given page.
    var onShowOnboarding: ((OnboardingStep) -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let session: SessionController
    private let settings: Settings
    private let devices = DeviceMenuSection()
    private var lastError: String?

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let connectItem = NSMenuItem(title: "", action: #selector(connectOrDisconnect), keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggleMode), keyEquivalent: "")
    private let retryItem = NSMenuItem(title: "지금 다시 연결", action: #selector(retryNow), keyEquivalent: "")
    private let deviceSectionAnchor = NSMenuItem.separator()
    private let speedMenu = NSMenu()
    private let powerMenu = NSMenu()
    private let capsLockMenu = NSMenu()
    /// First line of the Caps Lock menu: which host the choice applies to.
    private let capsLockScopeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let autoResumeItem = NSMenuItem(title: "재연결 시 iMac 입력 자동 복귀", action: #selector(toggleAutoResume), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLoginItem), keyEquivalent: "")
    private static let speedChoices: [Double] = [1.0, 1.5, 2.0, 2.5, 3.0, 4.0]

    init(session: SessionController, settings: Settings) {
        self.session = session
        self.settings = settings
        super.init()
        buildMenu()
        devices.onSelect = { [weak self] address, name in
            self?.lastError = nil
            self?.session.connect(toAddress: address, name: name)
        }
        devices.onForget = { [weak self] address in
            guard let self else { return }
            var hosts = self.settings.knownHosts
            hosts.forget(address: address)
            self.settings.knownHosts = hosts
        }
        session.onStateChange = { [weak self] state in self?.render(state) }
        session.statusItemFrame = { [weak self] in
            guard let button = self?.statusItem.button, let window = button.window else { return nil }
            return window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        session.onError = { [weak self] message in
            self?.lastError = message
            self?.render(session.state)
        }
        session.pairing.onNamesChanged = { [weak self] in self?.render(self?.session.state ?? .idle) }
        render(session.state)
    }

    // MARK: - Building

    private func buildMenu() {
        menu.delegate = self
        // Enabled state is decided in render(); AppKit's auto-enabling would override it.
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(deviceSectionAnchor)   // device rows are inserted before this separator

        connectItem.target = self
        menu.addItem(connectItem)
        toggleItem.target = self
        menu.addItem(toggleItem)
        retryItem.target = self
        retryItem.isHidden = true
        menu.addItem(retryItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "설정", action: nil, keyEquivalent: "")
        settingsItem.submenu = buildSettingsMenu()
        menu.addItem(settingsItem)

        let helpItem = NSMenuItem(title: "도움말", action: nil, keyEquivalent: "")
        helpItem.submenu = buildHelpMenu()
        menu.addItem(helpItem)

        let about = NSMenuItem(title: "\(AppInfo.name) 정보", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "\(AppInfo.name) 종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func buildSettingsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let speedItem = NSMenuItem(title: "포인터 배율", action: nil, keyEquivalent: "")
        speedItem.submenu = speedMenu
        for choice in Self.speedChoices {
            let item = NSMenuItem(title: String(format: "%.1f×", choice), action: #selector(selectSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice
            speedMenu.addItem(item)
        }
        menu.addItem(speedItem)

        let powerItem = NSMenuItem(title: "iMac 입력 중 절전", action: nil, keyEquivalent: "")
        powerItem.submenu = powerMenu
        for (mode, title) in [(PowerSaveMode.off, "끔"), (.dim, "화면 어둡게 (밝기 10%)"), (.blank, "화면 끄기 (밝기 0)")] {
            let item = NSMenuItem(title: title, action: #selector(selectPowerMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            powerMenu.addItem(item)
        }
        menu.addItem(powerItem)

        let capsItem = NSMenuItem(title: "Caps Lock → iMac", action: nil, keyEquivalent: "")
        capsItem.submenu = capsLockMenu
        capsLockMenu.autoenablesItems = false
        capsLockScopeItem.isEnabled = false
        capsLockMenu.addItem(capsLockScopeItem)
        capsLockMenu.addItem(.separator())
        let capsLockChoices: [(CapsLockMapping, String)] = [
            (.capsLock, "Caps Lock 그대로 (권장)"),
            (.globe, "🌐 키로 바꿔 보내기"),
            (.controlSpace, "⌃스페이스로 바꿔 보내기"),
        ]
        for (mapping, title) in capsLockChoices {
            let item = NSMenuItem(title: title, action: #selector(selectCapsLockMapping(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mapping.rawValue
            capsLockMenu.addItem(item)
        }
        capsLockMenu.addItem(.separator())
        let guide = NSMenuItem(title: "한/영 전환 설정 방법…", action: #selector(showInputSourceGuide), keyEquivalent: "")
        guide.target = self
        capsLockMenu.addItem(guide)
        menu.addItem(capsItem)
        menu.addItem(.separator())
        autoResumeItem.target = self
        menu.addItem(autoResumeItem)
        loginItem.target = self
        menu.addItem(loginItem)
        return menu
    }

    private func buildHelpMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let entries: [(String, Selector)] = [
            ("사용 방법 보기…", #selector(showGuide)),
            ("권한 확인…", #selector(requestPermissions)),
            ("문제 해결 안내…", #selector(openTroubleshooting)),
            ("진단 로그 내보내기…", #selector(exportDiagnostics)),
        ]
        for (title, action) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, action) in [("지원 웹사이트…", #selector(openWebsite)), ("문의하기…", #selector(contactSupport))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Rendering

    private func render(_ state: SessionState) {
        let target = settings.targetName ?? settings.targetAddress ?? "선택 안 됨"
        let hotkey = settings.hotkey.displayString
        let (symbol, description): (String, String)
        switch state {
        case .idle: (symbol, description) = ("keyboard", "대기 중 · 대상: \(target)")
        case .connecting:
            let kind = session.targetFamiliarity?.isFirstConnection == true ? "첫 연결" : "재연결"
            (symbol, description) = ("keyboard.badge.ellipsis", "연결 중… \(target) (\(kind))")
        case .connectedLocal: (symbol, description) = ("keyboard", "연결됨 · 입력: MacBook")
        case .connectedRemote: (symbol, description) = ("keyboard.fill", "연결됨 · 입력: iMac")
        case .disconnected:
            let retry = session.nextRetry.map { " · \(max(0, Int($0.timeIntervalSinceNow.rounded())))초 후 한 번 더 시도" } ?? ""
            (symbol, description) = ("keyboard.badge.ellipsis", "연결 끊김\(retry)")
        }
        let layerLine = Self.layerDescription(session.linkLayerStatus, state: state, hasTarget: settings.targetAddress != nil)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) {
            statusItem.button?.image = image
            statusItem.button?.contentTintColor = state == .connectedRemote ? .systemOrange : nil
        }
        statusItem.button?.toolTip = description
        statusLine.title = ([description] + [layerLine, lastError].compactMap { $0 }).joined(separator: "\n")

        let isActive = state != .idle
        let targetLabel = settings.targetName ?? settings.targetAddress
        connectItem.title = isActive ? "연결 해제" : (targetLabel.map { "‘\($0)’에 연결" } ?? "iMac에 연결 (먼저 기기를 선택)")
        connectItem.isEnabled = isActive || settings.targetAddress != nil
        toggleItem.title = state == .connectedRemote ? "MacBook 입력으로 전환 (\(hotkey))" : "iMac 입력으로 전환 (\(hotkey))"
        toggleItem.isEnabled = state == .connectedLocal || state == .connectedRemote
        retryItem.isHidden = !(state == .disconnected && session.isWaitingForUser)
    }

    /// What System Settings shows versus what the keyboard can do, while they differ.
    private static func layerDescription(_ status: LinkLayerStatus, state: SessionState, hasTarget: Bool) -> String? {
        guard hasTarget, state != .connectedLocal, state != .connectedRemote else { return nil }
        switch status {
        case .notPaired: return "블루투스: 페어링 안 됨"
        case .pairedOnly: return "블루투스: 페어링됨 · 링크 없음"
        case .basebandOnly: return "블루투스: 링크 연결됨 · 키보드 채널 없음"
        case .hidReady: return nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        let paired = session.pairing.pairedComputers()
        let familiarity = Dictionary(uniqueKeysWithValues: settings.knownHosts.entries.map {
            ($0.address, session.pairing.familiarity(of: $0.address))
        })
        devices.install(in: menu, above: deviceSectionAnchor, hosts: settings.knownHosts, targetAddress: settings.targetAddress,
                        isLinkUp: session.isLinkUp, paired: paired, familiarity: familiarity)
        for item in speedMenu.items {
            item.state = (item.representedObject as? Double) == settings.pointerMultiplier ? .on : .off
        }
        capsLockScopeItem.title = (settings.targetName ?? settings.targetAddress).map { "‘\($0)’에 적용" } ?? "모든 기기에 적용"
        for item in capsLockMenu.items where item.representedObject != nil {
            item.state = (item.representedObject as? String) == settings.capsLockMapping.rawValue ? .on : .off
        }
        for item in powerMenu.items {
            item.state = (item.representedObject as? String) == settings.powerSaveMode.rawValue ? .on : .off
            item.isEnabled = session.isPowerSaveAvailable || (item.representedObject as? String) == PowerSaveMode.off.rawValue
        }
        autoResumeItem.state = settings.autoResumeRemote ? .on : .off
        loginItem.state = SupportActions.isLoginItemEnabled ? .on : .off
        loginItem.title = SupportActions.loginItemNeedsApproval ? "로그인 시 자동 실행 (시스템 설정에서 승인 필요)" : "로그인 시 자동 실행"
        render(session.state)
    }

    // MARK: - Actions

    @objc private func connectOrDisconnect() {
        lastError = nil
        if session.state == .idle { session.connect() } else { session.disconnect() }
        render(session.state)
    }

    @objc private func toggleMode() { session.toggle() }
    @objc private func retryNow() {
        lastError = nil
        session.retryNow()
    }

    @objc private func selectSpeed(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        settings.pointerMultiplier = value
        session.applySettings()
    }

    @objc private func toggleAutoResume() { settings.autoResumeRemote.toggle() }

    @objc private func toggleLoginItem() {
        if let message = SupportActions.setLoginItem(enabled: !SupportActions.isLoginItemEnabled) {
            lastError = message
            render(session.state)
        }
    }

    @objc private func selectCapsLockMapping(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mapping = CapsLockMapping(rawValue: raw) else { return }
        var preferences = settings.capsLockPreferences
        preferences.set(mapping, for: settings.targetAddress)
        settings.capsLockPreferences = preferences
        session.applySettings()
    }

    @objc private func showInputSourceGuide() { onShowOnboarding?(.inputSource) }

    @objc private func selectPowerMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = PowerSaveMode(rawValue: raw) else { return }
        settings.powerSaveMode = mode
    }

    @objc private func requestPermissions() {
        InputPermissions.request()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "권한 상태"
        alert.informativeText = AppPermission.allCases.map { "\($0.title): \($0.isGranted ? "허용됨" : "필요")" }.joined(separator: "\n")
            + "\n\n시스템 설정 → 개인정보 보호 및 보안에서 \(AppInfo.name)을 허용하세요."
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "시스템 설정 열기")
        if alert.runModal() == .alertSecondButtonReturn {
            SystemSettingsLinks.open(AppPermission.allCases.first { !$0.isGranted }?.settingsURL ?? SystemSettingsLinks.accessibility)
        }
    }

    @objc private func showGuide() { onShowOnboarding?(.welcome) }
    @objc private func showAbout() { SupportActions.showAbout() }
    @objc private func openTroubleshooting() { NSWorkspace.shared.open(AppInfo.troubleshootingURL) }
    @objc private func openWebsite() { NSWorkspace.shared.open(AppInfo.websiteURL) }
    @objc private func contactSupport() { NSWorkspace.shared.open(AppInfo.supportMailURL) }

    @objc private func exportDiagnostics() {
        let summary = """
        대상: \(settings.targetName ?? "-") (\(settings.targetAddress ?? "-"))
        연결 의도: \(settings.wantsConnection), 일시 중지: \(settings.isPaused)
        포인터 배율: \(settings.pointerMultiplier), 절전: \(settings.powerSaveMode.rawValue), Caps Lock: \(settings.capsLockMapping.rawValue)
        자동 복귀: \(settings.autoResumeRemote), 권한: \(AppPermission.allCases.map { "\($0.title)=\($0.isGranted)" }.joined(separator: ", "))
        """
        SupportActions.exportDiagnostics(settingsSummary: summary) { [weak self] result in
            if case .failure(let error) = result {
                self?.lastError = "진단 로그를 저장하지 못했습니다: \(error.localizedDescription)"
                self?.render(self?.session.state ?? .idle)
            }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
