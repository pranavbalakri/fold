import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let blue = NSColor(calibratedRed: 0.21, green: 0.42, blue: 0.78, alpha: 1)

func drawText(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    (text as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 180), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
func makePDF(_ name: String, titles: [String]) throws {
    let url = folder.appendingPathComponent(name).appendingPathExtension("pdf")
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let context = CGContext(consumer: CGDataConsumer(url: url as CFURL)!, mediaBox: &box, nil)!
    for (index, title) in titles.enumerated() {
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 595, height: 842).fill()
        drawText("FOLD  /  FIELD NOTES", x: 48, y: 620, width: 500, size: 11, color: blue, weight: .semibold)
        drawText(title, x: 48, y: 470, width: 480, size: 46, color: NSColor(calibratedWhite: 0.15, alpha: 1), weight: .semibold)
        blue.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: NSRect(x: 48, y: 230, width: 499, height: 180), xRadius: 12, yRadius: 12).fill()
        drawText(index == 0 ? "The best tools give you your time back." : "Thoughtful details. A clearer point of view.", x: 72, y: 205, width: 440, size: 25, color: blue, weight: .medium)
        drawText("A sample document for trying out Fold’s PDF tools. Drag to reorder, select pages to rotate or remove, and save a new copy.", x: 48, y: 30, width: 460, size: 14, color: .gray)
        drawText(String(format: "%02d", index + 1), x: 500, y: -125, width: 50, size: 12, color: blue)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()
}
try makePDF("Field notes", titles: ["A little less\nfile friction.", "Room to\nthink.", "Every detail\ncounts."])
try makePDF("Project details", titles: ["Better\ntogether.", "On to the\nnext thing."])

let context = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(calibratedRed: 0.53, green: 0.76, blue: 0.88, alpha: 1).cgColor, NSColor(calibratedRed: 0.92, green: 0.91, blue: 0.81, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 800), end: .zero, options: [])
context.setFillColor(NSColor(calibratedRed: 0.97, green: 0.86, blue: 0.61, alpha: 1).cgColor)
context.fillEllipse(in: CGRect(x: 820, y: 490, width: 140, height: 140))
for (y, color) in [(240.0, NSColor(calibratedRed: 0.36, green: 0.52, blue: 0.52, alpha: 1)), (80.0, NSColor(calibratedRed: 0.23, green: 0.39, blue: 0.40, alpha: 1))] {
    context.setFillColor(color.cgColor)
    context.move(to: CGPoint(x: 0, y: y)); context.addCurve(to: CGPoint(x: 1200, y: y+80), control1: CGPoint(x: 380, y: y+500), control2: CGPoint(x: 700, y: y-230))
    context.addLine(to: CGPoint(x: 1200, y: 0)); context.addLine(to: .zero); context.closePath(); context.fillPath()
}
let image = context.makeImage()!
for type in [UTType.png, .heic] {
    let url = folder.appendingPathComponent("Quiet morning").appendingPathExtension(type.preferredFilenameExtension!)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn’t write \(url.lastPathComponent)") }
}
print("Created sample files in \(folder.path)")
