import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum ImageConverter {
    public static func convert(source: URL, output: URL, format: OutputFormat, quality: ExportQuality) throws {
        try Task.checkCancellation()
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw FoldError.message("“\(source.lastPathComponent)” couldn’t be opened as an image.")
        }
        guard CGImageSourceGetCount(imageSource) == 1 else {
            throw FoldError.message("This image contains multiple frames. Fold currently converts still images only, so no frames have been discarded.")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { throw FoldError.message("This image has no readable pixels.") }
        // Decode at original resolution and bake in EXIF orientation, including mirrored orientations.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw FoldError.message("macOS couldn’t decode this image. Try a PNG, JPEG, HEIC, or TIFF file.")
        }
        // JPEG has no alpha channel. Composite transparent images on white, never black.
        if format == .jpeg {
            guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw FoldError.message("There isn’t enough memory to convert this image.")
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = context.makeImage() else { throw FoldError.message("Couldn’t prepare the image.") }
            image = flattened
        }
        let staging = OutputFiles.stagingURL(for: output)
        defer { try? FileManager.default.removeItem(at: staging) }
        if format == .pdf {
            let document = PDFDocument()
            guard let page = PDFPage(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))) else {
                throw FoldError.message("Couldn’t create a PDF from this image.")
            }
            document.insert(page, at: 0)
            guard document.write(to: staging) else { throw FoldError.message("The PDF couldn’t be saved. Check the destination folder.") }
        } else {
            guard let type = format.imageType,
                  let destination = CGImageDestinationCreateWithURL(staging as CFURL, type.identifier as CFString, 1, nil) else {
                throw FoldError.message("This output format is not supported by this Mac.")
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality.imageQuality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw FoldError.message("The image couldn’t be saved. Check the destination folder.") }
        }
        try Task.checkCancellation()
        try OutputFiles.commit(staging, to: output)
    }
}
