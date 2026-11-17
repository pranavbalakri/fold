import Foundation
import PDFKit

public struct PDFPageReference: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let source: URL
    public let index: Int
    public var rotation: Int
    public init(source: URL, index: Int, rotation: Int = 0, id: UUID = UUID()) {
        self.id = id; self.source = source; self.index = index; self.rotation = rotation
    }
}

public enum PDFEditor {
    public static func pageCount(at url: URL) throws -> Int {
        let document = try open(url)
        return document.pageCount
    }

    private static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw FoldError.message("“\(url.lastPathComponent)” isn’t a readable PDF.") }
        guard !document.isLocked else { throw FoldError.message("“\(url.lastPathComponent)” is password-protected. Unlock it in Preview first.") }
        guard document.allowsCopying else { throw FoldError.message("“\(url.lastPathComponent)” doesn’t allow copying pages.") }
        guard document.pageCount > 0 else { throw FoldError.message("“\(url.lastPathComponent)” has no pages.") }
        return document
    }

    public static func merge(sources: [URL], output: URL) throws {
        guard sources.count >= 2 else { throw FoldError.message("Add at least two PDFs to merge.") }
        let pages = try sources.flatMap { source in
            try (0..<pageCount(at: source)).map { PDFPageReference(source: source, index: $0) }
        }
        try export(pages: pages, output: output)
    }

    public static func export(pages: [PDFPageReference], output: URL) throws {
        guard !pages.isEmpty else { throw FoldError.message("Keep at least one page to save a PDF.") }
        let result = PDFDocument()
        var documents: [URL: PDFDocument] = [:]
        for reference in pages {
            try Task.checkCancellation()
            let source: PDFDocument
            if let cached = documents[reference.source] { source = cached }
            else { source = try open(reference.source); documents[reference.source] = source }
            guard reference.index >= 0, reference.index < source.pageCount,
                  let original = source.page(at: reference.index), let copy = original.copy() as? PDFPage else {
                throw FoldError.message("Page \(reference.index + 1) could not be read.")
            }
            copy.rotation = ((original.rotation + reference.rotation) % 360 + 360) % 360
            result.insert(copy, at: result.pageCount)
        }
        result.documentAttributes = [PDFDocumentAttribute.creatorAttribute: "Fold"]
        let staging = OutputFiles.stagingURL(for: output)
        defer { try? FileManager.default.removeItem(at: staging) }
        guard result.write(to: staging) else { throw FoldError.message("The PDF couldn’t be saved. Check the destination folder.") }
        try Task.checkCancellation()
        try OutputFiles.commit(staging, to: output)
    }

    /// Parse human page ranges (1-based), preserving the requested order and rejecting mistakes.
    public static func parseRange(_ value: String, pageCount: Int) throws -> [Int] {
        guard pageCount > 0 else { throw FoldError.message("This PDF has no pages.") }
        var result: [Int] = []
        for segment in value.split(separator: ",", omittingEmptySubsequences: false) {
            let parts = segment.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
            if parts.count == 1, let number = Int(parts[0]), (1...pageCount).contains(number) {
                result.append(number - 1)
            } else if parts.count == 2,
                      let start = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                      let end = Int(parts[1].trimmingCharacters(in: .whitespaces)), start >= 1, end <= pageCount, start <= end {
                result.append(contentsOf: (start...end).map { $0 - 1 })
            } else { throw FoldError.message("Use page numbers from 1 to \(pageCount), like 1–3, 5. Use a hyphen for ranges.") }
        }
        var seen = Set<Int>()
        return result.filter { seen.insert($0).inserted }
    }
}
