import Foundation
import IOBluetooth
import HIDCore

/// Reads the pairing list in a helper process (`BTSKey --list-paired`) and hands the result to
/// the app. See `PairedDeviceRecord` for why the app must not read the list itself.
enum PairedDeviceLister {
    static let helperArgument = "--list-paired"
    private static let timeout: TimeInterval = 5

    enum ListerError: LocalizedError {
        case noExecutable
        case timedOut
        case failed(status: Int32)

        var errorDescription: String? {
            switch self {
            case .noExecutable: return "helper executable not found"
            case .timedOut: return "helper did not answer in time"
            case .failed(let status): return "helper exited with status \(status)"
            }
        }
    }

    /// Helper side: prints the pairing list as JSON. Runs in its own short-lived process.
    static func runHelper() -> Int32 {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let records = devices.compactMap { device -> PairedDeviceRecord? in
            guard let address = device.addressString else { return nil }
            return PairedDeviceRecord(address: address, name: device.name, classOfDevice: device.classOfDevice)
        }
        guard let data = try? PairedDeviceRecord.encodeList(records) else { return EXIT_FAILURE }
        FileHandle.standardOutput.write(data)
        return EXIT_SUCCESS
    }

    /// App side: runs the helper and decodes its output. Blocks; call it off the main thread.
    static func list() throws -> [PairedDeviceRecord] {
        guard let executable = Bundle.main.executableURL else { throw ListerError.noExecutable }
        let process = Process()
        process.executableURL = executable
        process.arguments = [helperArgument]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // The read below only returns when the helper closes its end, so the time limit has to be
        // armed first: terminating a helper that hangs (bluetoothd stalled, a permission prompt)
        // closes the pipe and lets the read return.
        let timeLimit = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeLimit)
        // Read before waiting: a full pipe would block the helper forever.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeLimit.cancel()
        guard process.terminationReason == .exit else { throw ListerError.timedOut }
        guard process.terminationStatus == EXIT_SUCCESS else { throw ListerError.failed(status: process.terminationStatus) }
        return try PairedDeviceRecord.decodeList(data)
    }
}
