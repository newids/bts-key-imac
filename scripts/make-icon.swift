// Renders the app icon (rounded square, gradient, keyboard glyph) into an .iconset and builds an .icns.
// Usage: swift scripts/make-icon.swift <output.icns>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.icns"
let iconset = URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let inset = size * 0.05
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.19, blue: 0.42, alpha: 1),
                        NSColor(calibratedRed: 0.06, green: 0.45, blue: 0.50, alpha: 1)])!
        .draw(in: path, angle: -60)
    // Soft highlight band across the top third.
    let highlight = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08), xRadius: rect.width * 0.2, yRadius: rect.width * 0.2)
    NSColor.white.withAlphaComponent(0.06).setFill()
    highlight.fill()
    // Keyboard glyph.
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
    if let glyph = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: glyph.size, flipped: false) { drawRect in
            glyph.draw(in: drawRect)
            NSColor.white.set()
            drawRect.fill(using: .sourceAtop)
            return true
        }
        let glyphRect = NSRect(x: (size - tinted.size.width) / 2, y: (size - tinted.size.height) / 2 + size * 0.02, width: tinted.size.width, height: tinted.size.height)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = size * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
        shadow.set()
        tinted.draw(in: glyphRect)
    }
    // Orange handoff dot: the "input goes elsewhere" accent used in the app.
    NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.0, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: rect.maxX - rect.width * 0.24, y: rect.minY + rect.height * 0.14, width: rect.width * 0.12, height: rect.width * 0.12)).fill()
    image.unlockFocus()
    return image
}

func write(_ image: NSImage, size: Int, name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}

for base in [16, 32, 128, 256, 512] {
    write(render(size: CGFloat(base)), size: base, name: "icon_\(base)x\(base).png")
    write(render(size: CGFloat(base * 2)), size: base * 2, name: "icon_\(base)x\(base)@2x.png")
}
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset.path, "-o", output]
task.launch()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "icon written to \(output)" : "iconutil failed")
exit(task.terminationStatus)
