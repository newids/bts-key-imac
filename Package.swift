// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BTSKey",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BTSKey", targets: ["BTSKeyApp"]),
        .library(name: "HIDCore", targets: ["HIDCore"]),
    ],
    targets: [
        // Pure logic: report descriptor, report encoders, keycode map, state machine.
        .target(name: "HIDCore"),
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
        .testTarget(name: "HIDCoreTests", dependencies: ["HIDCore"]),
        .testTarget(name: "ClassicHIDTransportTests", dependencies: ["ClassicHIDTransport"]),
        .testTarget(name: "InputCaptureTests", dependencies: ["InputCapture"]),
    ]
)
