import Foundation
import UniformTypeIdentifiers

public enum FileKind: String, Codable, Sendable {
    case image, video, audio, pdf

    public static func detect(_ url: URL) -> FileKind? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if ["heic", "heif", "png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp", "gif", "avif"].contains(ext) { return .image }
        if ["mov", "mp4", "m4v", "mkv", "webm", "avi", "mpg", "mpeg", "mts", "m2ts"].contains(ext) { return .video }
        if ["mp3", "m4a", "wav", "aiff", "aif", "flac", "ogg", "aac"].contains(ext) { return .audio }
        return nil
    }
}

public enum OutputFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case png, jpeg, heic, tiff, mp4, mov, m4v, webm, mkv, m4a, mp3, wav, pdf
    public var id: String { rawValue }
    public var label: String { self == .jpeg ? "JPG" : rawValue.uppercased() }
    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    public var kind: FileKind {
        switch self {
        case .png, .jpeg, .heic, .tiff: return .image
        case .mp4, .mov, .m4v, .webm, .mkv: return .video
        case .m4a, .mp3, .wav: return .audio
        case .pdf: return .pdf
        }
    }
    public var imageType: UTType? {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        default: return nil
        }
    }
    public static func available(for kind: FileKind, extendedVideo: Bool) -> [OutputFormat] {
        switch kind {
        case .image: return [.png, .jpeg, .heic, .tiff, .pdf]
        case .video: return extendedVideo ? [.mp4, .mov, .m4v, .webm, .mkv, .m4a, .mp3] : [.mp4, .mov, .m4v, .m4a]
        case .audio: return extendedVideo ? [.m4a, .mp3, .wav] : [.m4a]
        case .pdf: return [.pdf]
        }
    }
}

public enum ExportQuality: String, CaseIterable, Identifiable, Sendable {
    case high = "High quality", balanced = "Balanced", compact = "Smaller file"
    public var id: String { rawValue }
    public var imageQuality: Double {
        switch self { case .high: return 0.95; case .balanced: return 0.82; case .compact: return 0.65 }
    }
    public var crf: String {
        switch self { case .high: return "18"; case .balanced: return "23"; case .compact: return "28" }
    }
}

public enum FoldError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

public enum OutputFiles {
    /// Never replaces an existing file, including the source. All exporters write to a staging file first.
    public static func uniqueURL(directory: URL, stem: String, extension ext: String) -> URL {
        let clean = stem.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = clean.isEmpty ? "Untitled" : clean
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }

    public static func stagingURL(for output: URL) -> URL {
        output.deletingLastPathComponent().appendingPathComponent(".fold-\(UUID().uuidString)").appendingPathExtension(output.pathExtension)
    }

    public static func commit(_ staging: URL, to output: URL) throws {
        // moveItem fails if another process claimed the name while we were working.
        try FileManager.default.moveItem(at: staging, to: output)
    }
}
