import Foundation
import AVFoundation

public enum VideoConverter {
    public static var ffmpegURL: URL? {
        let paths = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ffmpeg").path,
                     "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    public static func convert(source: URL, output: URL, format: OutputFormat, quality: ExportQuality,
                               progress: @escaping @Sendable (Double) -> Void) async throws {
        let staging = OutputFiles.stagingURL(for: output)
        defer { try? FileManager.default.removeItem(at: staging) }
        try Task.checkCancellation()
        if let executable = ffmpegURL {
            let asset = AVURLAsset(url: source)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let runner = MediaProcess()
            let arguments = arguments(source: source, output: staging, format: format, quality: quality)
            try await runner.run(executable: executable, arguments: arguments, duration: duration, progress: progress)
        } else {
            try await nativeExport(source: source, output: staging, format: format, quality: quality, progress: progress)
        }
        try Task.checkCancellation()
        try OutputFiles.commit(staging, to: output)
        progress(1)
    }

    public static func arguments(source: URL, output: URL, format: OutputFormat, quality: ExportQuality) -> [String] {
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-i", source.path]
        if format.kind == .audio {
            args += ["-map", "0:a:0", "-vn"]
            switch format {
            case .mp3: args += ["-c:a", "libmp3lame", "-q:a", quality == .compact ? "5" : "2"]
            case .wav: args += ["-c:a", "pcm_s16le"]
            default: args += ["-c:a", "aac", "-b:a", quality == .compact ? "128k" : "256k"]
            }
        } else {
            args += ["-map", "0:v:0", "-map", "0:a:0?"]
            if format == .webm {
                args += ["-c:v", "libvpx-vp9", "-crf", quality == .high ? "25" : quality == .balanced ? "32" : "38",
                         "-b:v", "0", "-row-mt", "1", "-c:a", "libopus"]
            } else {
                args += ["-c:v", "libx264", "-preset", "fast", "-crf", quality.crf, "-c:a", "aac", "-b:a", "192k"]
                if format != .mkv { args += ["-movflags", "+faststart"] }
            }
            // H.264 and VP9 4:2:0 require even pixel dimensions. Keep aspect ratio and avoid enlargement.
            args += ["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-pix_fmt", "yuv420p"]
        }
        // FFmpeg otherwise treats .m4v as a raw elementary stream, losing its audio.
        if format == .m4v { args += ["-f", "mp4"] }
        args += ["-progress", "pipe:1", "-nostats", output.path]
        return args
    }

    static func nativeExport(source: URL, output: URL, format: OutputFormat, quality: ExportQuality,
                                     progress: @escaping @Sendable (Double) -> Void) async throws {
        let fileType: AVFileType
        switch format {
        case .mp4: fileType = .mp4
        case .mov: fileType = .mov
        case .m4v: fileType = .m4v
        case .m4a: fileType = .m4a
        default: throw FoldError.message("Install FFmpeg to convert this format. MP4, MOV, M4V, and M4A work with macOS built in.")
        }
        let preset = format == .m4a ? AVAssetExportPresetAppleM4A :
            quality == .high ? AVAssetExportPresetHighestQuality :
            quality == .balanced ? AVAssetExportPreset1920x1080 : AVAssetExportPreset1280x720
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: preset) else {
            throw FoldError.message("macOS can’t convert this video. Install FFmpeg for additional input formats.")
        }
        guard session.supportedFileTypes.contains(fileType) else { throw FoldError.message("This file can’t be exported as \(format.label) using macOS. Install FFmpeg for more formats.") }
        session.outputURL = output
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true
        let exporter = NativeExport(session: session)
        let monitor = Task {
            while !Task.isCancelled {
                progress(exporter.progress)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { monitor.cancel() }
        try await exporter.run()
    }
}

/// AVFoundation permits progress reads/cancellation while exporting; configuration is finished before sharing.
private final class NativeExport: @unchecked Sendable {
    private let session: AVAssetExportSession
    private let lock = NSLock()
    private var cancelled = false
    var progress: Double { Double(session.progress) }
    init(session: AVAssetExportSession) { self.session = session }
    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                guard !cancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                session.exportAsynchronously { [self] in
                    switch session.status {
                    case .completed: continuation.resume()
                    case .cancelled: continuation.resume(throwing: CancellationError())
                    default: continuation.resume(throwing: session.error ?? FoldError.message("The video couldn’t be converted."))
                    }
                }
                lock.unlock()
            }
        } onCancel: {
            self.lock.lock(); self.cancelled = true; self.session.cancelExport(); self.lock.unlock()
        }
    }
}

/// Launches arguments directly, drains both pipes, and terminates the child when its task is cancelled.
final class MediaProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var diagnostics = Data()
    private var progressBuffer = ""

    func run(executable: URL, arguments: [String], duration: Double,
             progress: @escaping @Sendable (Double) -> Void) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                let child = Process()
                let stdout = Pipe(), stderr = Pipe()
                child.executableURL = executable
                child.arguments = arguments
                child.standardOutput = stdout
                child.standardError = stderr
                child.standardInput = FileHandle.nullDevice
                stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let self else { return }
                    self.lock.lock()
                    self.progressBuffer += String(decoding: data, as: UTF8.self)
                    var fraction: Double?
                    while let newline = self.progressBuffer.firstIndex(of: "\n") {
                        let line = String(self.progressBuffer[..<newline])
                        self.progressBuffer.removeSubrange(...newline)
                        if line.hasPrefix("out_time_us="), duration.isFinite, duration > 0,
                           let microseconds = Double(line.dropFirst(12)) {
                            fraction = min(0.99, max(0, microseconds / 1_000_000 / duration))
                        }
                    }
                    self.lock.unlock()
                    if let fraction { progress(fraction) }
                }
                stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    guard let self, !data.isEmpty else { return }
                    self.lock.lock()
                    self.diagnostics.append(data)
                    if self.diagnostics.count > 12_000 { self.diagnostics = self.diagnostics.suffix(12_000) }
                    self.lock.unlock()
                }
                child.terminationHandler = { [weak self] finished in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    guard let self else { continuation.resume(throwing: CancellationError()); return }
                    self.lock.lock()
                    let wasCancelled = self.cancelled
                    let details = String(decoding: self.diagnostics, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    self.process = nil
                    self.lock.unlock()
                    if wasCancelled { continuation.resume(throwing: CancellationError()) }
                    else if finished.terminationStatus == 0 { continuation.resume() }
                    else { continuation.resume(throwing: FoldError.message(details.isEmpty ? "The video couldn’t be converted. The file may be damaged or use an unsupported codec." : "Conversion failed: \(details.suffix(1500))")) }
                }
                process = child
                do { try child.run(); lock.unlock() }
                catch {
                    process = nil
                    lock.unlock()
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            if let process = self.process, process.isRunning { process.terminate() }
            self.lock.unlock()
        }
    }
}
