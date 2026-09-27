import AppKit
import IOBluetooth
import HIDCore

/// The device rows at the top of the menu: icon + name, like the macOS Bluetooth menu.
/// Known hosts (connected before) come first; other paired computers sit in a submenu.
final class DeviceMenuSection {
    var onSelect: ((_ address: String, _ name: String) -> Void)?
    var onForget: ((_ address: String) -> Void)?

    private let otherDevicesMenu = NSMenu()
    private let emptyItem = NSMenuItem(title: "연결한 적 있는 기기 없음", action: nil, keyEquivalent: "")
    private var rows: [NSMenuItem] = []
    private let otherItem: NSMenuItem

    init() {
        otherItem = NSMenuItem(title: "다른 페어링된 기기", action: nil, keyEquivalent: "")
        otherItem.submenu = otherDevicesMenu
        otherDevicesMenu.autoenablesItems = false
        emptyItem.isEnabled = false
    }

    /// Rebuilds the rows in `menu` just above `anchor`. Old rows are removed first, so the
    /// anchor's index is read only after that removal.
    func install(in menu: NSMenu, above anchor: NSMenuItem, hosts: KnownHosts, targetAddress: String?, isLinkUp: Bool,
                 paired: [PairedDeviceWatcher.PairedComputer]) {
        rows.forEach { if menu.items.contains($0) { menu.removeItem($0) } }
        rows = []
        var cursor = menu.index(of: anchor)
        guard cursor >= 0 else { return }
        if hosts.entries.isEmpty {
            rows.append(emptyItem)
        }
        for host in hosts.entries {
            let item = NSMenuItem(title: host.name, action: #selector(rowSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = host
            item.image = Self.icon(for: host.kind)
            let isTarget = InboundPolicy.isSameHost(host.address, targetAddress)
            let isPaired = paired.contains { $0.address == host.address }
            item.state = isTarget && isLinkUp ? .on : .off
            item.isEnabled = isPaired
            let status = isTarget && isLinkUp ? "연결됨" : (isPaired ? Self.lastSeen(host.lastConnected) : "페어링 해제됨")
            if #available(macOS 14.4, *) {
                item.subtitle = status
            } else if isTarget && isLinkUp || !isPaired {
                item.title = "\(host.name) — \(status)"
            }
            item.submenu = contextMenu(for: host, isConnected: isTarget && isLinkUp)
            rows.append(item)
        }
        rebuildOtherDevices(excluding: hosts, paired: paired)
        rows.append(otherItem)
        for row in rows {
            menu.insertItem(row, at: cursor)
            cursor += 1
        }
    }

    private func contextMenu(for host: KnownHost, isConnected: Bool) -> NSMenu {
        let menu = NSMenu()
        let connect = NSMenuItem(title: isConnected ? "연결됨" : "연결", action: #selector(rowSelected(_:)), keyEquivalent: "")
        connect.target = self
        connect.representedObject = host
        connect.isEnabled = !isConnected
        menu.addItem(connect)
        menu.addItem(.separator())
        let forget = NSMenuItem(title: "목록에서 제거", action: #selector(forgetSelected(_:)), keyEquivalent: "")
        forget.target = self
        forget.representedObject = host
        menu.addItem(forget)
        return menu
    }

    private func rebuildOtherDevices(excluding hosts: KnownHosts, paired: [PairedDeviceWatcher.PairedComputer]) {
        otherDevicesMenu.removeAllItems()
        let candidates = paired.filter { !hosts.contains(address: $0.address) }
        if candidates.isEmpty {
            let none = NSMenuItem(title: "페어링된 컴퓨터가 없습니다", action: nil, keyEquivalent: "")
            none.isEnabled = false
            otherDevicesMenu.addItem(none)
        }
        for computer in candidates {
            // Names missing from the cache are being looked up; show the address only until then.
            let title = computer.hasResolvedName ? computer.name : "\(computer.name) (이름 조회 중…)"
            let item = NSMenuItem(title: title, action: #selector(rowSelected(_:)), keyEquivalent: "")
            item.target = self
            item.image = Self.icon(for: computer.kind)
            item.representedObject = KnownHost(address: computer.address, name: computer.name, kind: computer.kind, lastConnected: 0)
            otherDevicesMenu.addItem(item)
        }
        otherDevicesMenu.addItem(.separator())
        let open = NSMenuItem(title: "Bluetooth 설정 열기…", action: #selector(openBluetoothSettings), keyEquivalent: "")
        open.target = self
        otherDevicesMenu.addItem(open)
    }

    private static func icon(for kind: BluetoothDeviceKind) -> NSImage? {
        let image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private static func lastSeen(_ time: Double) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return "마지막 연결 " + formatter.localizedString(for: Date(timeIntervalSince1970: time), relativeTo: Date())
    }

    @objc private func rowSelected(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? KnownHost else { return }
        onSelect?(host.address, host.name)
    }

    @objc private func forgetSelected(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? KnownHost else { return }
        onForget?(host.address)
    }

    @objc private func openBluetoothSettings() {
        SystemSettingsLinks.open(SystemSettingsLinks.bluetooth)
    }
}
