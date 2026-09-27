import AppKit
import ServiceManagement
import os

/// About panel, login item, and diagnostics export used by the Help menu and onboarding.
enum SupportActions {
    private static let log = Logger(subsystem: "btskey", category: "support")

    static func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(string: "MacBook을 iMac의 블루투스 키보드·마우스로.\n\n", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        credits.append(NSAttributedString(string: "지원: \(AppInfo.supportEmail)\n\(AppInfo.websiteURL.absoluteString)", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .version: AppInfo.build,
            .credits: credits,
        ])
    }

    // MARK: - Login item

    static var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS registered the item but waits for the user to approve it in Login Items.
    static var loginItemNeedsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Returns a user-facing message when the change failed or still needs approval.
    @discardableResult
    static func setLoginItem(enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if enabled, loginItemNeedsApproval {
                SMAppService.openSystemSettingsLoginItems()
                return "시스템 설정 → 일반 → 로그인 항목에서 \(AppInfo.name)을 허용해야 자동 실행됩니다."
            }
            return nil
        } catch {
            log.error("login item change failed: \(error.localizedDescription, privacy: .public)")
            return "로그인 항목을 바꾸지 못했습니다: \(error.localizedDescription)"
        }
    }

    // MARK: - Diagnostics

    /// Collects the app's own log and Bluetooth inventory into a text file on the Desktop and reveals it.
    static func exportDiagnostics(settingsSummary: String, completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try writeDiagnostics(settingsSummary: settingsSummary) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func writeDiagnostics(settingsSummary: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let stamp = formatter.string(from: Date())
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = desktop.appendingPathComponent("\(AppInfo.name) 진단 \(stamp).txt")

        var text = """
        \(AppInfo.name) \(AppInfo.versionLine)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        생성 \(Date())

        [설정]
        \(settingsSummary)

        [앱 로그, 최근 2시간]

        """
        text += run("/usr/bin/log", ["show", "--last", "2h", "--predicate", "subsystem == \"btskey\"", "--style", "compact"])
        text += "\n[Bluetooth 장치]\n\n"
        text += run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-detailLevel", "mini"])
        try text.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return "(\(path) 실행 실패: \(error.localizedDescription))\n"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
