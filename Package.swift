// swift-tools-version: 5.10
import PackageDescription

// Pure logic: report descriptor, report encoders, keycode map, state machine.
// Imports Foundation only, so it builds wherever Swift does (see docs/windows-build.md).
let portableTargets: [Target] = [
    .target(name: "HIDCore"),
    .testTarget(name: "HIDCoreTests", dependencies: ["HIDCore"]),
]

#if os(macOS)
let platformProducts: [Product] = [
    .executable(name: "BTSKey", targets: ["BTSKeyApp"]),
]
let platformTargets: [Target] = [
    // Bluetooth Classic HID device emulation via IOBluetooth (plan A).
    .target(
        name: "ClassicHIDTransport",
        dependencies: ["HIDCore"],
        linkerSettings: [.linkedFramework("IOBluetooth")]
    ),
    // CGEventTap-based keyboard/trackpad capture and cursor lock.
    .target(
        name: "InputCapture",
        dependencies: ["HIDCore"],
        linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("CoreGraphics"), .linkedFramework("IOKit"), .linkedFramework("Carbon")]
    ),
    // Menu bar application.
    .executableTarget(
        name: "BTSKeyApp",
        dependencies: ["HIDCore", "ClassicHIDTransport", "InputCapture"],
        linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("IOBluetooth")]
    ),
    .testTarget(name: "ClassicHIDTransportTests", dependencies: ["ClassicHIDTransport"]),
    .testTarget(name: "InputCaptureTests", dependencies: ["InputCapture"]),
]
#else
// The transport, input capture and app targets use Apple frameworks; other platforms
// get the core and its tests only.
let platformProducts: [Product] = []
let platformTargets: [Target] = []
#endif

let package = Package(
    name: "BTSKey",
    platforms: [.macOS(.v13)],
    products: [.library(name: "HIDCore", targets: ["HIDCore"])] + platformProducts,
    targets: portableTargets + platformTargets
)
