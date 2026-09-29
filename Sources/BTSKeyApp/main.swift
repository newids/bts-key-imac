import AppKit

// The pairing list is read by a copy of this executable that exits right away (see PairedDeviceLister).
if CommandLine.arguments.contains(PairedDeviceLister.helperArgument) {
    exit(PairedDeviceLister.runHelper())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
