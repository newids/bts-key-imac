import Foundation
import IOBluetooth
import HIDCore
import os

/// Polls the paired-computer list so the app notices when the user pairs a new iMac
/// (make it the target) or forgets one (stop retrying it). Also resolves missing device
/// names asynchronously so the menu never has to show a bare address.
final class PairedDeviceWatcher: NSObject {
    struct PairedComputer: Equatable {
        let address: String
        let name: String
        let kind: BluetoothDeviceKind
        let hasResolvedName: Bool
    }

    var onAdded: ((PairedComputer) -> Void)?
    var onRemoved: ((_ address: String) -> Void)?
    /// Fires after a background name lookup so menus can re-render.
    var onNamesChanged: (() -> Void)?

    private static let interval: TimeInterval = 5
    private let log = Logger(subsystem: "btskey", category: "pairing")
    private var timer: Timer?
    private var known: Set<String>?
    private var removalDebounce = PairingRemovalDebounce()
    private var pendingNameLookups: Set<String> = []
    private var lastNames: [String: String]?

    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Paired computers right now (cheap XPC; safe to call from menu code).
    /// bluetoothd lists a freshly paired Mac twice and names it with a UUID until the first
    /// connection resolves the real name; both are hidden from the user here.
    func pairedComputers() -> [PairedComputer] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        var seen: Set<String> = []
        return devices.compactMap { device in
            guard let raw = device.addressString else { return nil }
            let address = InboundPolicy.normalize(raw)
            guard seen.insert(address).inserted else { return nil }
            let kind = BluetoothDeviceKind(classOfDevice: device.classOfDevice)
            guard kind.canHostKeyboard else { return nil }
            let resolved = Self.resolvedName(device.name)
            if resolved == nil { requestName(of: device) }
            return PairedComputer(address: address, name: resolved ?? Self.placeholderName(for: address), kind: kind, hasResolvedName: resolved != nil)
        }
    }

    /// A real name, or nil for empty names and the UUID placeholders macOS uses before the first connection.
    static func resolvedName(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return UUID(uuidString: name) == nil ? name : nil
    }

    /// "Mac (7c:99)" — recognizable from the last octets in the iMac's own Bluetooth settings.
    static func placeholderName(for address: String) -> String {
        let tail = address.split(separator: "-").suffix(2).joined(separator: ":")
        return "Mac (\(tail))"
    }

    /// The current resolved name of a paired computer, if macOS knows it by now.
    func resolvedName(of address: String) -> String? {
        IOBluetoothDevice(addressString: address).flatMap { Self.resolvedName($0.name) }
    }

    /// nil when the list is unavailable (empty), so callers do not mistake a daemon hiccup for "unpaired".
    func isPaired(address: String) -> Bool? {
        let computers = pairedComputers()
        guard !computers.isEmpty else { return nil }
        return computers.contains { InboundPolicy.isSameHost($0.address, address) }
    }

    func poll() {
        let computers = pairedComputers()
        let now = Set(computers.map(\.address))
        let change = PairingChange(before: known, after: now)
        if !(now.isEmpty && !(known ?? []).isEmpty) { known = now }
        let names = Dictionary(uniqueKeysWithValues: computers.map { ($0.address, $0.name) })
        if names != lastNames, lastNames != nil { onNamesChanged?() }
        lastNames = names
        let removed = removalDebounce.confirmedRemovals(candidates: change.removed)
        guard !change.added.isEmpty || !removed.isEmpty else { return }
        for address in removed {
            log.notice("pairing removed: \(address, privacy: .public)")
            onRemoved?(address)
        }
        for address in change.added {
            guard let computer = computers.first(where: { $0.address == address }) else { continue }
            log.notice("pairing added: \(computer.name, privacy: .public) (\(address, privacy: .public))")
            onAdded?(computer)
        }
    }

    private func requestName(of device: IOBluetoothDevice) {
        guard let address = device.addressString, !pendingNameLookups.contains(address) else { return }
        pendingNameLookups.insert(address)
        // Async: the synchronous variant pages the device and would block the main thread.
        let status = device.remoteNameRequest(self)
        if status != kIOReturnSuccess { pendingNameLookups.remove(address) }
    }

    @objc func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        if let address = device.addressString { pendingNameLookups.remove(address) }
        guard status == kIOReturnSuccess else { return }
        onNamesChanged?()
    }
}
