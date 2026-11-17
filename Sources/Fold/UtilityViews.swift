import SwiftUI
import AppKit
import FoldCore

struct RecentView: View {
    @ObservedObject var model: AppModel
    @State private var confirmClear = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Recent exports").font(.system(size: 28, weight: .semibold)).tracking(-0.65)
                        Text("Your files, ready for what’s next.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.recents.isEmpty { Button("Clear history") { confirmClear = true }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                if model.recents.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.tertiary)
                        Text("A fresh page.").font(.system(size: 18, weight: .semibold))
                        Text("Your finished files will appear here,\nready to open or find in Finder.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Convert your first file") { model.workspace = .convert }.buttonStyle(QuietButtonStyle()).padding(.top, 8)
                    }.frame(maxWidth: .infinity).frame(height: 360)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.recents) { recent in
                            HStack(spacing: 13) {
                                Image(systemName: recent.url.pathExtension == "pdf" ? "doc.richtext" : "doc").font(.system(size: 22, weight: .light)).foregroundStyle(Palette.blue).frame(width: 40, height: 44).background(Palette.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(recent.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                    Text("\(recent.operation) · \(ByteCountFormatter.string(fromByteCount: recent.size, countStyle: .file))").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(recent.date, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary)
                                IconButton(symbol: "folder", help: "Show in Finder") { model.reveal([recent.url]) }
                                IconButton(symbol: "arrow.up.right", help: "Open exported file") { model.open(recent.url) }
                            }.padding(.vertical, 14)
                            Divider()
                        }
                    }
                }
            }.padding(34)
        }.confirmationDialog("Clear export history?", isPresented: $confirmClear) {
            Button("Clear history") { model.recents = []; model.saveHistory() }
        } message: { Text("Your exported files will stay exactly where they are.") }
    }
}

struct MergeOrderSheet: View {
    @ObservedObject var model: AppModel
    let drop: MergeDrop
    @Environment(\.dismiss) var dismiss
    @State private var before = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack").font(.system(size: 24, weight: .light)).foregroundStyle(Palette.blue)
                VStack(alignment: .leading, spacing: 4) { Text("A place for every PDF.").font(.system(size: 20, weight: .semibold)); Text("Where should \(drop.urls.count == 1 ? "this PDF go" : "these PDFs go")?").foregroundStyle(.secondary) }
            }
            VStack(spacing: 9) {
                orderOption(value: true, label: "Before", symbol: "arrow.up.to.line")
                orderOption(value: false, label: "After", symbol: "arrow.down.to.line")
            }
            HStack {
                Text("Original files stay untouched.").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add to merge") {
                    let index = model.pdfs.firstIndex { $0.id == drop.target } ?? model.pdfs.count
                    model.importURLs(drop.urls, mode: .merge, insertAt: index + (before ? 0 : 1))
                    dismiss()
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 450)
    }
    func orderOption(value: Bool, label: String, symbol: String) -> some View {
        Button { before = value } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Palette.blue).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) { Text(label).font(.system(size: 13, weight: .medium)); Text(drop.targetName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Image(systemName: before == value ? "largecircle.fill.circle" : "circle").foregroundStyle(before == value ? Palette.blue : .secondary)
            }.padding(14).background(before == value ? Palette.blue.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(before == value ? Palette.blue.opacity(0.5) : Palette.line, lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) { FoldMark(size: 40); VStack(alignment: .leading, spacing: 3) { Text("Make yourself at home.").font(.system(size: 21, weight: .semibold)); Text("A few small things, just your way.").foregroundStyle(.secondary).font(.system(size: 12)) } }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $model.shortcutEnabled) {
                        VStack(alignment: .leading, spacing: 5) { Text("Finder keyboard shortcut").fontWeight(.medium); Text("Bring selected files into Fold with ⌃⌥Space.").font(.system(size: 11)).foregroundStyle(.secondary) }
                    }.toggleStyle(.switch)
                    if model.shortcutEnabled && !model.shortcutRegistered { Label("This shortcut is in use by another app. Finder Services and drag-and-drop are still available.", systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange) }
                    Divider()
                    HStack {
                        Text("Appearance")
                        Spacer()
                        Picker("Appearance", selection: $model.appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.labelsHidden().pickerStyle(.segmented).frame(width: 225)
                    }
                    Divider()
                    HStack { Text("Default export quality"); Spacer(); Picker("Quality", selection: $model.quality) { ForEach(ExportQuality.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 145) }
                    Divider()
                    HStack(alignment: .top) {
                        Text("Video formats")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Label(model.extendedVideo ? "Extended formats available" : "Built-in formats", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(model.extendedVideo ? "FFmpeg is installed on this Mac." : "MP4, MOV, M4V, and M4A. Install FFmpeg for WebM, MKV, and MP3.").font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: 240, alignment: .trailing)
                        }
                    }
                }.padding(12)
            }
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                Text("Your files never leave your Mac. Fold saves a new copy, keeps your originals, and won’t overwrite an existing file.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack { Text("Fold 0.1 · Made for the little things.").font(.system(size: 10)).foregroundStyle(.tertiary); Spacer(); Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 500)
    }
}

struct QuickPanelView: View {
    @ObservedObject var model: AppModel
    let resize: (CGFloat) -> Void
    let openWorkspace: () -> Void
    var panelHeight: CGFloat {
        model.workspace == .pages ? 430 : min(500, 230 + CGFloat(max(1, model.currentCount)) * 64)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                FoldMark(size: 35)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.workspace.title).font(.system(size: 19, weight: .semibold))
                    Text("A quick change. Then back to it.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open full workspace", action: openWorkspace).disabled(model.isBusy || model.isImporting)
            }
            if model.isImporting { Spacer(); ProgressView("Preparing files…").frame(maxWidth: .infinity); Spacer() }
            else if model.workspace == .pages {
                VStack(spacing: 14) {
                    FileArtwork(mode: .pages)
                    Text("\(model.pages.count) pages, ready to arrange.").font(.system(size: 14, weight: .medium))
                    Text("Reorder, rotate, remove, or extract pages\nin your workspace.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Organize pages", action: openWorkspace).buttonStyle(PrimaryButtonStyle())
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 9) {
                        if model.workspace == .merge {
                            ForEach(Array(model.pdfs.enumerated()), id: \.element.id) { index, file in
                                HStack(spacing: 10) {
                                    FileThumbnail(file: file, size: 34)
                                    VStack(alignment: .leading, spacing: 4) { Text(file.url.lastPathComponent).lineLimit(1); Text(file.detail).font(.system(size: 10)).foregroundStyle(.secondary) }
                                    Spacer()
                                    IconButton(symbol: "chevron.up", help: "Move PDF up") { if index > 0 { model.pdfs.swapAt(index, index - 1) } }.disabled(index == 0 || model.isBusy)
                                    IconButton(symbol: "chevron.down", help: "Move PDF down") { if index + 1 < model.pdfs.count { model.pdfs.swapAt(index, index + 1) } }.disabled(index + 1 == model.pdfs.count || model.isBusy)
                                }.padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            }
                        } else {
                            ForEach($model.files) { $file in
                                HStack(spacing: 10) {
                                    FileThumbnail(file: file, size: 34)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.url.lastPathComponent).lineLimit(1)
                                        if let failure = file.failure { Text(failure).font(.system(size: 10)).foregroundStyle(.red).lineLimit(3) }
                                        else { Text(file.output == nil ? file.detail : "Ready").font(.system(size: 10)).foregroundStyle(file.output == nil ? Color.secondary : .green) }
                                    }
                                    Spacer()
                                    Picker("Format", selection: $file.format) { ForEach(OutputFormat.available(for: file.kind, extendedVideo: model.extendedVideo)) { Text($0.label).tag($0) } }.labelsHidden().frame(width: 82).disabled(model.isBusy || file.output != nil)
                                }.padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                if let completion = model.completion { Text(completion).font(.system(size: 12)).foregroundStyle(model.lastOutputs.isEmpty ? Color.secondary : .green) }
                if model.isBusy { ProgressView(value: model.progress).progressViewStyle(.linear) }
                HStack {
                    Label("Saved beside the originals", systemImage: "folder").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    if model.isBusy { Button("Cancel") { model.cancel() }.buttonStyle(QuietButtonStyle()) }
                    else if !model.lastOutputs.isEmpty && model.completion != nil {
                        Button("Show in Finder") { model.reveal(model.lastOutputs) }.buttonStyle(PrimaryButtonStyle())
                        if model.canRun && model.workspace == .convert { Button("Retry") { model.run() }.buttonStyle(QuietButtonStyle()) }
                    } else {
                        Button(model.workspace == .merge ? "Merge PDFs" : "Convert files") { model.run() }.buttonStyle(PrimaryButtonStyle()).disabled(!model.canRun)
                    }
                }
            }
        }.font(.system(size: 12)).padding(24).padding(.top, 18).frame(width: 510, height: panelHeight).background(.regularMaterial).tint(Palette.blue)
            .ignoresSafeArea(.container, edges: .top)
            .onChange(of: panelHeight, initial: true) { _, height in resize(height) }
            .alert(item: $model.issue) { issue in Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK"))) }
    }
}

struct FinderHelpView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            FoldMark(size: 44)
            VStack(alignment: .leading, spacing: 8) { Text("Less opening. More doing.").font(.system(size: 25, weight: .semibold)).tracking(-0.5); Text("Fold fits into the way you already use your Mac.").font(.system(size: 13)).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 22) {
                helpRow("command", title: "Start from Finder", text: "Select your files, then press Control–Option–Space. On first use, macOS asks to let Fold read your Finder selection.")
                helpRow("cursorarrow.click", title: "Or use the right-click menu", text: "Move Fold to Applications and open it once. In Finder, right-click selected files → Services → Convert with Fold, Merge PDFs with Fold, or Edit PDF Pages with Fold.")
                helpRow("square.stack", title: "Drop. Arrange. Done.", text: "Drag files into Fold. In Merge PDFs, drop a PDF onto another to pick before or after. In Organize pages, drag to reorder, select to rotate or remove, and extract only what you need.")
            }
            Text("If Services aren’t visible, enable them in System Settings → Keyboard → Keyboard Shortcuts → Services. Fold keeps running in the menu bar when you close its window.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Got it") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 480)
    }
    func helpRow(_ symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Palette.blue).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 13, weight: .semibold)); Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(3) }
        }
    }
}
