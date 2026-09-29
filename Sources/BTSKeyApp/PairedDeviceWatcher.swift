import Foundation
import IOBluetooth
import HIDCore
import os

/// Polls the paired-device list so the app notices when the user pairs a new iMac
/// (make it the target) or forgets one (stop retrying it). The list is compared against a
/// ledger kept on disk, so a pairing made while the app was not running is noticed at launch.
///
/// The list itself is read by a helper process (`PairedDeviceLister`); this class only ever
/// sees its decoded output. Every paired device is tracked, not only computers: an iMac that
/// started the pairing itself is stored without a class of device, so the class cannot tell it
/// from a phone. What tells them apart is the ledger (see `BluetoothDeviceKind.isHostCandidate`).
///
/// This class never pages a device. Looking up a missing name with `remoteNameRequest` opened a
/// baseband link of its own to every unnamed computer, which collided with the connection
/// attempt to a freshly paired iMac and paged iMacs the user was not sitting at; a computer
/// without a name is shown under a placeholder until its first connection resolves it.
final class PairedDeviceWatcher: NSObject {
    struct PairedComputer: Equatable {
        let address: String
        let name: String
        let kind: BluetoothDeviceKind
        let hasResolvedName: Bool
    }

    /// Computers paired since the last look, all at once: more than one means the app cannot
    /// tell which the user wants.
    var onAdded: (([PairedComputer]) -> Void)?
    var onRemoved: ((_ address: String) -> Void)?
    /// Fires when a name changed between two polls so menus can re-render.
    var onNamesChanged: (() -> Void)?
    /// Fires once, after the first list has been processed (and `onAdded` has run for it).
    var onFirstList: (() -> Void)?

    private static let interval: TimeInterval = 5
    private let log = Logger(subsystem: "btskey", category: "pairing")
    private let settings: Settings
    private let queue = DispatchQueue(label: "btskey.pairing-list", qos: .utility)
    private var timer: Timer?
    private var isListing = false
    private var hasDeliveredFirstList = false
    private var lastNames: [String: String]?
    /// The devices of the last successful poll; menus read this instead of asking again.
    private var devices: [PairedComputer] = []
    /// Held in memory between polls: the ledger's removal debounce is not part of what is stored.
    private var ledger: PairingLedger

    init(settings: Settings) {
        self.settings = settings
        ledger = settings.pairingLedger
    }

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

    /// Paired devices that can be offered as a host, as of the last poll.
    func pairedComputers() -> [PairedComputer] {
        hostCandidates(among: devices)
    }

    private func hostCandidates(among devices: [PairedComputer]) -> [PairedComputer] {
        devices.filter { $0.kind.isHostCandidate(familiarity: familiarity(of: $0.address, isPaired: true)) }
    }

    /// A real name, or nil for empty names and the UUID placeholders macOS uses before the first connection.
    static func resolvedName(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return UUID(uuidString: name) == nil ? name : nil
    }

    /// "Mac (aa:01)" — recognizable from the last octets in the iMac's own Bluetooth settings.
    static func placeholderName(for address: String) -> String {
        let tail = address.split(separator: "-").suffix(2).joined(separator: ":")
        return "Mac (\(tail))"
    }

    /// The current resolved name of a paired computer, if macOS knows it by now.
    func resolvedName(of address: String) -> String? {
        IOBluetoothDevice(addressString: address).flatMap { Self.resolvedName($0.name) }
    }

    /// Asks the device record directly; this does not depend on the polled list.
    func isPaired(address: String) -> Bool {
        IOBluetoothDevice(addressString: address)?.isPaired() ?? false
    }

    /// How well this Mac knows `address`, from the pairing ledger and the connection history.
    func familiarity(of address: String) -> HostFamiliarity {
        familiarity(of: address, isPaired: isPaired(address: address))
    }

    private func familiarity(of address: String, isPaired: Bool) -> HostFamiliarity {
        let lastServed = settings.knownHosts.entries.first { InboundPolicy.isSameHost($0.address, address) }?.lastConnected
        return HostFamiliarity(isPaired: isPaired, pairedSince: ledger.pairedSince(address), lastServed: lastServed)
    }

    func poll() {
        guard !isListing else { return }
        isListing = true
        queue.async { [weak self] in
            let result = Result { try PairedDeviceLister.list() }
            DispatchQueue.main.async { self?.finishPoll(result) }
        }
    }

    private func finishPoll(_ result: Result<[PairedDeviceRecord], Error>) {
        isListing = false
        switch result {
        case .failure(let error):
            log.error("pairing list unavailable: \(error.localizedDescription, privacy: .public)")
        case .success(let records):
            process(records.map { record in
                let resolved = Self.resolvedName(record.name)
                return PairedComputer(address: record.address, name: resolved ?? Self.placeholderName(for: record.address),
                                      kind: record.kind, hasResolvedName: resolved != nil)
            })
        }
        guard !hasDeliveredFirstList else { return }
        hasDeliveredFirstList = true
        onFirstList?()
    }

    private func process(_ current: [PairedComputer]) {
        // An empty list means the daemon is restarting or Bluetooth is off; keep what is known.
        guard !current.isEmpty else { return }
        devices = current
        let change = ledger.observe(paired: Set(current.map(\.address)), at: Date().timeIntervalSince1970)
        if !change.isEmpty || settings.pairingLedger != ledger { settings.pairingLedger = ledger }
        let computers = hostCandidates(among: current)
        let names = Dictionary(uniqueKeysWithValues: computers.map { ($0.address, $0.name) })
        if names != lastNames, lastNames != nil { onNamesChanged?() }
        lastNames = names
        for address in change.removed {
            log.notice("pairing removed: \(address, privacy: .public)")
            onRemoved?(address)
        }
        for device in current where change.added.contains(device.address) && !computers.contains(device) {
            // No name here: this is one of the user's other devices and the log can end up in a diagnostics file.
            log.notice("pairing added but not a host (\(String(describing: device.kind), privacy: .public))")
        }
        let added = computers.filter { change.added.contains($0.address) }
        guard !added.isEmpty else { return }
        for computer in added {
            log.notice("pairing added: \(computer.name, privacy: .public) (\(computer.address, privacy: .public)) class \(String(describing: computer.kind), privacy: .public)")
        }
        onAdded?(added)
    }
}
