import AppKit
import SwiftUI
import PDFKit
import ImageIO
import FoldCore

enum Workspace: String, CaseIterable, Identifiable {
    case convert, merge, pages, recent
    var id: String { rawValue }
    var title: String {
        switch self { case .convert: return "Convert files"; case .merge: return "Merge PDFs"; case .pages: return "Organize pages"; case .recent: return "Recent exports" }
    }
    var symbol: String {
        switch self { case .convert: return "arrow.triangle.2.circlepath"; case .merge: return "square.stack"; case .pages: return "rectangle.split.3x1"; case .recent: return "clock" }
    }
    var subtitle: String {
        switch self {
        case .convert: return "A new format. A fresh start."
        case .merge: return "Bring your documents together."
        case .pages: return "Every page, in its place."
        case .recent: return "Your files, ready for what’s next."
        }
    }
}

struct InputFile: Identifiable {
    let id: UUID
    let url: URL
    let kind: FileKind
    let size: Int64
    let pageCount: Int
    let thumbnail: NSImage?
    var format: OutputFormat
    var output: URL?
    var failure: String?
    var progress: Double = 0
    var isRunning = false
    var detail: String {
        if kind == .pdf { return "\(pageCount) \(pageCount == 1 ? "page" : "pages") · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))" }
        return "\(url.pathExtension.uppercased()) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
    }

    static func load(_ url: URL) throws -> InputFile {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw FoldError.message("Choose files instead of folders.") }
        guard let kind = FileKind.detect(url) else { throw FoldError.message("“\(url.lastPathComponent)” isn’t supported yet.") }
        let count = kind == .pdf ? try PDFEditor.pageCount(at: url) : 0
        let thumbnail: NSImage?
        if kind == .pdf { thumbnail = PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: NSSize(width: 220, height: 280), for: .cropBox) }
        else if kind == .image, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 160, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
            thumbnail = NSImage(cgImage: cg, size: .zero)
        } else { thumbnail = nil }
        return InputFile(id: UUID(), url: url, kind: kind, size: Int64(values.fileSize ?? 0), pageCount: count, thumbnail: thumbnail,
                         format: kind == .image ? .png : kind == .audio ? .m4a : kind == .pdf ? .pdf : .mp4)
    }
}

struct PageItem: Identifiable {
    var reference: PDFPageReference
    let thumbnail: NSImage?
    var id: UUID { reference.id }
}

struct RecentExport: Identifiable, Codable {
    let id: UUID
    let url: URL
    let operation: String
    let date: Date
    let size: Int64
}

struct UserIssue: Identifiable { let id = UUID(); let title: String; let message: String }
struct MergeDrop: Identifiable { let id = UUID(); let urls: [URL]; let target: UUID; let targetName: String }
struct PreviewItem: Identifiable { let url: URL; var id: URL { url } }

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var workspace: Workspace = .convert
    @Published var files: [InputFile] = []
    @Published var pdfs: [InputFile] = []
    @Published var pages: [PageItem] = []
    @Published var selectedPages: Set<UUID> = []
    @Published var recents: [RecentExport] = []
    @Published var quality: ExportQuality = ExportQuality(rawValue: UserDefaults.standard.string(forKey: "exportQuality") ?? "") ?? .high {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "exportQuality") }
    }
    @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system" {
        didSet {
            UserDefaults.standard.set(appearance, forKey: "appearance")
            NSApp.appearance = appearance == "light" ? NSAppearance(named: .aqua) : appearance == "dark" ? NSAppearance(named: .darkAqua) : nil
        }
    }
    @Published var destination: URL?
    @Published var outputName = "Merged document"
    @Published var isBusy = false
    @Published var isImporting = false
    @Published var progress = 0.0
    @Published var status = ""
    @Published var completion: String?
    @Published var lastOutputs: [URL] = []
    @Published var issue: UserIssue?
    @Published var mergeDrop: MergeDrop?
    @Published var preview: PreviewItem?
    @Published var showingSettings = false
    @Published var showingHelp = false
    @Published var rangeText = ""
    @Published var pageHistory: [[PageItem]] = []
    @Published var shortcutEnabled = UserDefaults.standard.object(forKey: "shortcutEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(shortcutEnabled, forKey: "shortcutEnabled"); NotificationCenter.default.post(name: .foldShortcutChanged, object: nil) }
    }
    @Published var shortcutRegistered = false
    var workTask: Task<Void, Never>?
    var extendedVideo: Bool { VideoConverter.ffmpegURL != nil }
    var currentCount: Int {
        switch workspace { case .convert: return files.count; case .merge: return pdfs.count; case .pages: return pages.count; case .recent: return recents.count }
    }
    var canRun: Bool {
        guard !isBusy, !isImporting else { return false }
        switch workspace {
        case .convert: return files.contains { $0.output == nil }
        case .merge: return pdfs.count >= 2
        case .pages: return !pages.isEmpty
        case .recent: return false
        }
    }
    private var historyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fold/History.json")
    }

    init() {
        reloadHistory()
    }
    func reloadHistory() {
        if let data = try? Data(contentsOf: historyURL), let decoded = try? JSONDecoder().decode([RecentExport].self, from: data) { recents = decoded }
    }

    func chooseFiles() {
        guard !isBusy, !isImporting else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = workspace == .merge || workspace == .pages ? [.pdf] : [.image, .movie, .audio, .pdf, .data]
        panel.prompt = "Add files"
        panel.message = workspace == .merge ? "Choose PDFs to bring together." : workspace == .pages ? "Choose a PDF to arrange its pages." : "Choose images, videos, audio, or PDFs."
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.importURLs(panel.urls) }
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Save here"
        panel.message = "Choose where Fold saves your new files."
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.destination = panel.url }
        }
    }

    func importURLs(_ urls: [URL], mode requestedMode: Workspace? = nil, insertAt: Int? = nil, preset: OutputFormat? = nil) {
        guard !isBusy, !isImporting else {
            issue = UserIssue(title: "One moment", message: "Wait for the current operation to finish before adding more files.")
            return
        }
        guard !urls.isEmpty else { return }
        var mode = requestedMode ?? workspace
        let allPDFs = urls.allSatisfy { FileKind.detect($0) == .pdf }
        if mode == .recent || (mode == .convert && allPDFs) { mode = allPDFs ? (urls.count > 1 ? .merge : .pages) : .convert }
        workspace = mode
        completion = nil
        isImporting = true
        let chosenMode = mode
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([InputFile], [PageItem], [String]) in
                var loaded: [InputFile] = [], loadedPages: [PageItem] = [], problems: [String] = []
                for url in urls {
                    do {
                        let file = try InputFile.load(url)
                        guard (chosenMode == .convert && file.kind != .pdf) || (chosenMode != .convert && file.kind == .pdf) else {
                            throw FoldError.message(chosenMode == .convert ? "Add PDFs in Merge PDFs or Organize pages." : "“\(url.lastPathComponent)” isn’t a PDF.")
                        }
                        loaded.append(file)
                        if chosenMode == .pages, let document = PDFDocument(url: url) {
                            for index in 0..<document.pageCount {
                                loadedPages.append(PageItem(reference: PDFPageReference(source: url, index: index), thumbnail: document.page(at: index)?.thumbnail(of: NSSize(width: 240, height: 310), for: .cropBox)))
                            }
                        }
                    } catch { problems.append(error.localizedDescription) }
                }
                return (loaded, loadedPages, problems)
            }.value
            if chosenMode == .convert {
                for var file in result.0 where !files.contains(where: { $0.url == file.url }) {
                    if let preset, OutputFormat.available(for: file.kind, extendedVideo: extendedVideo).contains(preset) { file.format = preset }
                    files.append(file)
                }
            } else if chosenMode == .merge {
                let fresh = result.0.filter { file in !pdfs.contains { $0.url == file.url } }
                pdfs.insert(contentsOf: fresh, at: min(insertAt ?? pdfs.count, pdfs.count))
            } else {
                if !result.1.isEmpty {
                    rememberPages()
                    pages.append(contentsOf: result.1)
                    if let first = result.0.first, pages.count == result.1.count { outputName = first.url.deletingPathExtension().lastPathComponent + " edited" }
                }
            }
            isImporting = false
            if !result.2.isEmpty { issue = UserIssue(title: "Some files couldn’t be added", message: result.2.joined(separator: "\n\n")) }
        }
    }

    func applyPreset(_ format: OutputFormat) {
        workspace = .convert
        if files.isEmpty {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = format.kind == .image ? [.image] : [.movie, .data]
            panel.prompt = "Add files"
            panel.begin { [weak self] response in
                guard response == .OK else { return }
                Task { @MainActor in self?.importURLs(panel.urls, mode: .convert, preset: format) }
            }
        } else {
            for index in files.indices where files[index].output == nil && OutputFormat.available(for: files[index].kind, extendedVideo: extendedVideo).contains(format) { files[index].format = format }
        }
    }

    func clearWorkspace() {
        guard !isBusy else { return }
        switch workspace {
        case .convert: files = []
        case .merge: pdfs = []; outputName = "Merged document"
        case .pages: pages = []; selectedPages = []; pageHistory = []; outputName = "Edited document"
        case .recent: break
        }
        completion = nil; lastOutputs = []
    }

    func run(extract: Bool = false) {
        guard canRun else { return }
        completion = nil; lastOutputs = []; isBusy = true; progress = 0
        let mode = workspace, chosenQuality = quality, folder = destination
        let name = outputName.trimmingCharacters(in: .whitespacesAndNewlines)
        workTask = Task {
            defer { isBusy = false; status = ""; workTask = nil }
            do {
                if mode == .convert {
                    let pending = files.filter { $0.output == nil }
                    var failed = 0
                    for (offset, file) in pending.enumerated() {
                        try Task.checkCancellation()
                        status = "Converting \(offset + 1) of \(pending.count)"
                        updateFile(file.id) { $0.isRunning = true; $0.failure = nil; $0.progress = 0 }
                        let output = OutputFiles.uniqueURL(directory: folder ?? file.url.deletingLastPathComponent(), stem: file.url.deletingPathExtension().lastPathComponent, extension: file.format.fileExtension)
                        do {
                            if file.kind == .image {
                                try await cancellableDetached { try ImageConverter.convert(source: file.url, output: output, format: file.format, quality: chosenQuality) }
                            } else {
                                try await VideoConverter.convert(source: file.url, output: output, format: file.format, quality: chosenQuality) { [weak self] fraction in
                                    Task { @MainActor in
                                        self?.updateFile(file.id) { $0.progress = fraction }
                                        self?.progress = (Double(offset) + fraction) / Double(pending.count)
                                    }
                                }
                            }
                            updateFile(file.id) { $0.output = output; $0.isRunning = false; $0.progress = 1 }
                            record(output, operation: "Converted to \(file.format.label)")
                            lastOutputs.append(output)
                        } catch is CancellationError { updateFile(file.id) { $0.isRunning = false }; throw CancellationError() }
                        catch { failed += 1; updateFile(file.id) { $0.isRunning = false; $0.failure = error.localizedDescription } }
                        progress = Double(offset + 1) / Double(pending.count)
                    }
                    completion = failed == 0 ? "\(lastOutputs.count) \(lastOutputs.count == 1 ? "file is" : "files are") ready." : "\(lastOutputs.count) exported · \(failed) couldn’t be converted."
                } else {
                    let chosenPages = extract ? pages.filter { selectedPages.contains($0.id) } : pages
                    let source = mode == .merge ? pdfs.first?.url : chosenPages.first?.reference.source
                    guard let source else { throw FoldError.message("Select at least one page to extract.") }
                    let stem = name.isEmpty ? (mode == .merge ? "Merged document" : "Edited document") : name
                    let output = OutputFiles.uniqueURL(directory: folder ?? source.deletingLastPathComponent(), stem: stem + (extract ? " extracted" : ""), extension: "pdf")
                    status = mode == .merge ? "Bringing your PDFs together…" : "Preparing your pages…"
                    let sources = pdfs.map(\.url), references = chosenPages.map(\.reference)
                    try await cancellableDetached {
                        if mode == .merge { try PDFEditor.merge(sources: sources, output: output) }
                        else { try PDFEditor.export(pages: references, output: output) }
                    }
                    record(output, operation: mode == .merge ? "Merged \(sources.count) PDFs" : "\(extract ? "Extracted" : "Saved") \(references.count) pages")
                    lastOutputs = [output]; progress = 1; completion = "Your PDF is ready."
                }
            } catch is CancellationError { completion = lastOutputs.isEmpty ? "Cancelled. Your originals are untouched." : "Cancelled. \(lastOutputs.count) finished exports were kept." }
            catch { issue = UserIssue(title: "Couldn’t finish", message: error.localizedDescription) }
        }
    }

    func cancel() { workTask?.cancel() }
    func updateFile(_ id: UUID, _ change: (inout InputFile) -> Void) {
        if let index = files.firstIndex(where: { $0.id == id }) { change(&files[index]) }
    }
    func record(_ url: URL, operation: String) {
        reloadHistory()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        recents.insert(RecentExport(id: UUID(), url: url, operation: operation, date: Date(), size: Int64(size)), at: 0)
        recents = Array(recents.prefix(100)); saveHistory()
    }
    func saveHistory() {
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(recents).write(to: historyURL, options: .atomic)
        } catch { /* History is optional; exported files are already safely on disk. */ }
    }
    func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    func open(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { issue = UserIssue(title: "File not found", message: "This file may have been moved or deleted since it was exported."); return }
        NSWorkspace.shared.open(url)
    }
    func rememberPages() { pageHistory.append(pages); if pageHistory.count > 20 { pageHistory.removeFirst() } }
    func undoPages() { if let previous = pageHistory.popLast() { pages = previous; selectedPages.formIntersection(Set(pages.map(\.id))) } }
    func rotatePages() {
        guard !selectedPages.isEmpty else { return }
        rememberPages()
        for index in pages.indices where selectedPages.contains(pages[index].id) { pages[index].reference.rotation = (pages[index].reference.rotation + 90) % 360 }
    }
    func removePages() {
        guard !selectedPages.isEmpty else { return }
        rememberPages(); pages.removeAll { selectedPages.contains($0.id) }; selectedPages = []
    }
    func selectRange() {
        do { selectedPages = Set(try PDFEditor.parseRange(rangeText.replacingOccurrences(of: "–", with: "-"), pageCount: pages.count).map { pages[$0].id }) }
        catch { issue = UserIssue(title: "Check the page range", message: error.localizedDescription) }
    }
    func movePDF(_ id: UUID, to target: UUID) {
        guard let from = pdfs.firstIndex(where: { $0.id == id }), let to = pdfs.firstIndex(where: { $0.id == target }), from != to else { return }
        let file = pdfs.remove(at: from); pdfs.insert(file, at: to)
    }
    func movePage(_ id: UUID, to target: UUID) {
        guard let from = pages.firstIndex(where: { $0.id == id }), let to = pages.firstIndex(where: { $0.id == target }), from != to else { return }
        rememberPages(); let page = pages.remove(at: from); pages.insert(page, at: to)
    }
}

private func cancellableDetached(_ operation: @escaping @Sendable () throws -> Void) async throws {
    let task = Task.detached(priority: .userInitiated) { try Task.checkCancellation(); try operation() }
    try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
}

extension Notification.Name {
    static let foldShortcutChanged = Notification.Name("foldShortcutChanged")
}
