import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 80, y: 80, width: 864, height: 864)
let path = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 32; shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState(); shadow.set()
NSColor.systemBlue.setFill(); path.fill(); NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor(calibratedRed: 0.38, green: 0.66, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.14, green: 0.36, blue: 0.88, alpha: 1))!.draw(in: path, angle: -80)
if let symbol = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 500, weight: .medium)) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus(); NSColor.white.set(); NSRect(origin: .zero, size: symbol.size).fill(); symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1); tinted.unlockFocus()
    let width: CGFloat = 570, height = width * symbol.size.height / symbol.size.width
    tinted.draw(in: NSRect(x: (1024-width)/2, y: (1024-height)/2, width: width, height: height))
}
image.unlockFocus()
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
