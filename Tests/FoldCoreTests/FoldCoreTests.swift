import XCTest
import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import AVFoundation
@testable import FoldCore

final class FoldCoreTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FoldTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testHEICToPNGBakesOrientationAndPreservesSource() throws {
        let source = directory.appendingPathComponent("Portrait.heic")
        try imageFixture(source, type: .heic, orientation: 6)
        let original = try Data(contentsOf: source)
        let output = directory.appendingPathComponent("Portrait.png")
        try ImageConverter.convert(source: source, output: output, format: .png, quality: .high)
        let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        XCTAssertEqual(image.width, 48)
        XCTAssertEqual(image.height, 96)
        XCTAssertEqual(CGImageSourceGetType(decoded) as String?, UTType.png.identifier)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testTransparentPNGFlattensToWhiteJPEG() throws {
        let source = directory.appendingPathComponent("Transparent.png")
        try imageFixture(source, type: .png, transparent: true)
        let output = directory.appendingPathComponent("White.jpg")
        try ImageConverter.convert(source: source, output: output, format: .jpeg, quality: .high)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
        let color = try XCTUnwrap(rep.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.9)
        XCTAssertGreaterThan(color.greenComponent, 0.9)
        XCTAssertGreaterThan(color.blueComponent, 0.9)
    }

    func testImageToPDF() throws {
        let source = directory.appendingPathComponent("Photo.png")
        try imageFixture(source, type: .png)
        let output = directory.appendingPathComponent("Photo.pdf")
        try ImageConverter.convert(source: source, output: output, format: .pdf, quality: .high)
        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 1)
    }

    func testAnimatedImageIsRejectedInsteadOfLosingFrames() throws {
        let source = directory.appendingPathComponent("Animated.gif")
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.gif.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertThrowsError(try ImageConverter.convert(source: source, output: directory.appendingPathComponent("Still.png"), format: .png, quality: .high))
    }

    func testMergeOrderAndSourcePreservation() throws {
        let first = try pdfFixture("First", widths: [200, 220])
        let second = try pdfFixture("Second", widths: [300])
        let original = try Data(contentsOf: first)
        let output = directory.appendingPathComponent("Merged.pdf")
        try PDFEditor.merge(sources: [second, first], output: output)
        let pdf = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(pdf.pageCount, 3)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).width, 300)
        XCTAssertEqual(pdf.page(at: 1)?.bounds(for: .mediaBox).width, 200)
        XCTAssertEqual(pdf.page(at: 2)?.bounds(for: .mediaBox).width, 220)
        XCTAssertEqual(try Data(contentsOf: first), original)
    }

    func testPageRemovalReorderingAndRotation() throws {
        let source = try pdfFixture("Pages", widths: [200, 220, 240, 260])
        let output = directory.appendingPathComponent("Edited.pdf")
        try PDFEditor.export(pages: [PDFPageReference(source: source, index: 3, rotation: 90), PDFPageReference(source: source, index: 1)], output: output)
        let pdf = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).width, 260)
        XCTAssertEqual(pdf.page(at: 0)?.rotation, 90)
        XCTAssertEqual(pdf.page(at: 1)?.bounds(for: .mediaBox).width, 220)
        XCTAssertEqual(PDFDocument(url: source)?.pageCount, 4)
        XCTAssertEqual(PDFDocument(url: source)?.page(at: 3)?.rotation, 0)
    }

    func testInvalidAndLockedPDFsAreRejected() throws {
        let source = try pdfFixture("Locked", widths: [200])
        let locked = directory.appendingPathComponent("Encrypted.pdf")
        let document = try XCTUnwrap(PDFDocument(url: source))
        XCTAssertTrue(document.write(to: locked, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        XCTAssertThrowsError(try PDFEditor.pageCount(at: locked))
        XCTAssertThrowsError(try PDFEditor.export(pages: [], output: directory.appendingPathComponent("Empty.pdf")))
        XCTAssertThrowsError(try PDFEditor.export(pages: [PDFPageReference(source: source, index: 9)], output: directory.appendingPathComponent("Invalid.pdf")))
        XCTAssertThrowsError(try PDFEditor.merge(sources: [source], output: directory.appendingPathComponent("One.pdf")))
    }

    func testRangesPreserveOrderAndValidateBoundaries() throws {
        XCTAssertEqual(try PDFEditor.parseRange("3, 1-2, 2, 5", pageCount: 5), [2, 0, 1, 4])
        for value in ["", "0", "6", "3-1", "1-6", "1,", "1--2", "hello", "-1"] {
            XCTAssertThrowsError(try PDFEditor.parseRange(value, pageCount: 5), "Should reject \(value)")
        }
    }

    func testOutputNeverReplacesAnExistingFileAndCleansStaging() throws {
        let source = directory.appendingPathComponent("Original.png")
        try imageFixture(source, type: .png)
        let original = try Data(contentsOf: source)
        XCTAssertEqual(OutputFiles.uniqueURL(directory: directory, stem: "Original", extension: "png").lastPathComponent, "Original 2.png")
        XCTAssertThrowsError(try ImageConverter.convert(source: source, output: source, format: .png, quality: .high))
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".fold-") })
    }

    func testFFmpegVideoConversionProducesPlayableMovie() async throws {
        guard let ffmpeg = VideoConverter.ffmpegURL else { throw XCTSkip("FFmpeg not installed") }
        let source = directory.appendingPathComponent("Clip with spaces.mov")
        try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=blue:s=160x120:r=12:d=0.5", "-c:v", "libx264", "-pix_fmt", "yuv420p", source.path])
        let output = directory.appendingPathComponent("Converted.mp4")
        try await VideoConverter.convert(source: source, output: output, format: .mp4, quality: .balanced) { _ in }
        let asset = AVURLAsset(url: output)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        XCTAssertTrue(playable)
        XCTAssertGreaterThan(duration.seconds, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCancellationStopsChildAndRemovesPartialOutput() async throws {
        guard let ffmpeg = VideoConverter.ffmpegURL else { throw XCTSkip("FFmpeg not installed") }
        let source = directory.appendingPathComponent("Long.mov")
        try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=s=640x480:r=30:d=5", "-c:v", "libx264", "-preset", "ultrafast", source.path])
        let output = directory.appendingPathComponent("Cancelled.webm")
        let task = Task { try await VideoConverter.convert(source: source, output: output, format: .webm, quality: .high) { _ in } }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Expected CancellationError: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".fold-") })
    }

    func testM4VPreservesAudioAndNativeExportWorksWithoutFFmpeg() async throws {
        guard let ffmpeg = VideoConverter.ffmpegURL else { throw XCTSkip("FFmpeg is only needed to generate this fixture") }
        let source = directory.appendingPathComponent("With audio.mov")
        try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=blue:s=160x120:r=12:d=0.5", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.5", "-c:v", "libx264", "-c:a", "aac", "-shortest", source.path])
        let m4v = directory.appendingPathComponent("With audio.m4v")
        try await VideoConverter.convert(source: source, output: m4v, format: .m4v, quality: .balanced) { _ in }
        let audioTracks = try await AVURLAsset(url: m4v).loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1, "M4V must use an MP4 container, not a silent raw stream")
        let native = directory.appendingPathComponent("Native.mp4")
        try await VideoConverter.nativeExport(source: source, output: native, format: .mp4, quality: .high) { _ in }
        let playable = try await AVURLAsset(url: native).load(.isPlayable)
        XCTAssertTrue(playable)
    }

    private func imageFixture(_ url: URL, type: UTType, orientation: Int = 1, transparent: Bool = false) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 96, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if !transparent { context.setFillColor(NSColor.systemBlue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 96, height: 48)) }
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func pdfFixture(_ name: String, widths: [CGFloat]) throws -> URL {
        let url = directory.appendingPathComponent(name).appendingPathExtension("pdf")
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        var box = CGRect(x: 0, y: 0, width: widths[0], height: 400)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for width in widths {
            var pageBox = CGRect(x: 0, y: 0, width: width, height: 400)
            let boxData = Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            context.setFillColor(NSColor.systemBlue.cgColor)
            context.fill(CGRect(x: 20, y: 20, width: 50, height: 50))
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
    private func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    }
}
