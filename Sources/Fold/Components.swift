import SwiftUI
import AppKit
import PDFKit
import FoldCore
import UniformTypeIdentifiers

enum Palette {
    static let blue = Color(red: 0.18, green: 0.43, blue: 0.91)
    static let line = Color.primary.opacity(0.085)
    static let canvas = Color(nsColor: .controlBackgroundColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
}

struct MaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .sidebar; view.blendingMode = .behindWindow; view.state = .active; return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct FoldMark: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25).fill(LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 1), Palette.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: size * 0.53, weight: .medium)).foregroundStyle(.white)
        }.frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(.white.opacity(0.22), lineWidth: 1))
            .shadow(color: Palette.blue.opacity(0.15), radius: 6, y: 3)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(Color.primary.opacity(configuration.isPressed ? 0.085 : 0.045), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 0.5))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(enabled ? .white : Color.secondary)
            .padding(.horizontal, 18).frame(height: 36)
            .background(enabled ? Palette.blue.opacity(configuration.isPressed ? 0.8 : 1) : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 6).frame(height: 22)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(help).accessibilityLabel(help)
    }
}

struct FileThumbnail: View {
    let file: InputFile
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.08))
            if let image = file.thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(file.kind == .pdf ? 4 : 0)
            } else {
                Image(systemName: file.kind == .audio ? "waveform" : file.kind == .video ? "film" : "doc").font(.system(size: size * 0.4)).foregroundStyle(color)
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 0.5))
    }
    var color: Color { file.kind == .pdf ? .red : file.kind == .video ? .purple : Palette.blue }
}

struct FileArtwork: View {
    let mode: Workspace
    var body: some View {
        ZStack {
            Circle().fill(Palette.blue.opacity(0.035)).frame(width: 160, height: 160)
            miniCard(label: mode == .convert ? "HEIC" : "PDF", symbol: mode == .convert ? "photo" : "text.alignleft", color: mode == .convert ? Color.secondary : Color(red: 0.85, green: 0.35, blue: 0.32))
                .rotationEffect(.degrees(-12)).offset(x: -35, y: 5)
            miniCard(label: mode == .convert ? "PNG" : "PDF", symbol: mode == .convert ? "photo.fill" : "text.alignleft", color: Palette.blue)
                .rotationEffect(.degrees(9)).offset(x: 35, y: -5)
            Image(systemName: mode == .convert ? "arrow.right" : mode == .merge ? "plus" : "scissors")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.blue)
                .frame(width: 33, height: 33).background(Palette.canvas, in: Circle())
                .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1)).offset(y: 25)
        }.frame(height: 130).accessibilityHidden(true)
    }
    func miniCard(label: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 27, weight: .light)).foregroundStyle(color.opacity(0.7))
            Text(label).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(color)
        }.frame(width: 76, height: 96)
            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 6)
    }
}

struct DropArea: View {
    let mode: Workspace
    var compact = false
    let busy: Bool
    let add: () -> Void
    let receive: ([URL]) -> Void
    @State private var targeted = false
    var body: some View {
        VStack(spacing: compact ? 5 : 8) {
            if !compact { FileArtwork(mode: mode) }
            HStack(spacing: 6) {
                if compact { Image(systemName: "plus.circle").foregroundStyle(Palette.blue) }
                Text(targeted ? "Drop them right here" : compact ? "Drop more files here" : mode == .convert ? "Drop your files here" : mode == .merge ? "Drop your PDFs here" : "Drop a PDF here")
                    .font(.system(size: compact ? 13 : 18, weight: compact ? .medium : .semibold))
            }
            if !compact {
                Text(mode == .convert ? "Images, videos, and audio. One file or a whole batch." : mode == .merge ? "Arrange them your way. We’ll make them one." : "Keep the pages you need. Put them in the right order.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button(action: add) { HStack(spacing: 6) { Text("Choose files"); Text("⌘O").foregroundStyle(.secondary) } }
                    .buttonStyle(QuietButtonStyle()).padding(.top, 10)
            }
        }.frame(maxWidth: .infinity).frame(height: compact ? 64 : 286)
            .background(targeted ? Palette.blue.opacity(0.065) : Color.primary.opacity(0.012), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(targeted ? Palette.blue : Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [5, 5])))
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                guard !busy else { return false }; readDroppedURLs(providers, completion: receive); return true
            }
            .disabled(busy)
    }
}

func readDroppedURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    Task { @MainActor in
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let url = item as? URL { continuation.resume(returning: url) }
                    else if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                    else if let string = item as? String { continuation.resume(returning: URL(string: string)) }
                    else { continuation.resume(returning: nil) }
                }
            }
            if let url, url.isFileURL { urls.append(url) }
        }
        completion(urls)
    }
}

struct PDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url); return view
    }
    func updateNSView(_ view: PDFView, context: Context) { if view.document?.documentURL != url { view.document = PDFDocument(url: url) } }
}
