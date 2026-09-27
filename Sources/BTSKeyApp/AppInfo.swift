import Foundation

/// Product identity and support destinations shown in About/Help.
enum AppInfo {
    static let name = "BTS Key"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "kr.newid.btskey"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    static let copyright = "© 2026 newid"

    /// Distribution and support pages; the download page lives next to `docs/distribution.md`.
    static let websiteURL = URL(string: "https://newids.github.io/bts-key-imac/")!
    static let helpURL = URL(string: "https://newids.github.io/bts-key-imac/#usage")!
    static let troubleshootingURL = URL(string: "https://github.com/newids/bts-key-imac/blob/main/docs/connection-audit.md")!
    static let supportEmail = "newids@gmail.com"

    static var supportMailURL: URL {
        let subject = "\(name) \(version) 문의".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(supportEmail)?subject=\(subject)")!
    }

    static var versionLine: String { "버전 \(version) (\(build))" }
}
