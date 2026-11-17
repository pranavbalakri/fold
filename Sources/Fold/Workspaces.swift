import SwiftUI
import UniformTypeIdentifiers
import FoldCore

struct ConversionList: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("\(model.files.count) \(model.files.count == 1 ? "FILE" : "FILES")").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.tertiary); Spacer(); Text("CONVERT TO").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.tertiary).padding(.trailing, 42) }
            VStack(spacing: 0) {
                ForEach($model.files) { $file in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            FileThumbnail(file: file)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(file.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                if file.isRunning { ProgressView(value: file.progress).progressViewStyle(.linear).frame(maxWidth: 180) }
                                else { Text(file.output != nil ? "Ready · \(file.output!.lastPathComponent)" : file.detail).font(.system(size: 10)).foregroundStyle(file.output != nil ? Color.green : .secondary) }
                            }
                            Spacer(minLength: 14)
                            if file.output != nil {
                                IconButton(symbol: "folder", help: "Show exported file in Finder") { if let output = file.output { model.reveal([output]) } }
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(.horizontal, 8)
                            } else {
                                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                                Picker("Output format", selection: $file.format) {
                                    ForEach(OutputFormat.available(for: file.kind, extendedVideo: model.extendedVideo)) { format in Text(format.label).tag(format) }
                                }.labelsHidden().frame(width: 85).disabled(model.isBusy)
                            }
                            IconButton(symbol: "xmark", help: "Remove \(file.url.lastPathComponent)") { model.files.removeAll { $0.id == file.id } }.disabled(model.isBusy)
                        }.padding(14)
                        if let failure = file.failure { Label(failure, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.red).padding(.horizontal, 15).padding(.bottom, 12).textSelection(.enabled) }
                    }
                    if file.id != model.files.last?.id { Divider().padding(.leading, 68) }
                }
            }.background(Color.primary.opacity(0.016), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line, lineWidth: 1))
            DropArea(mode: .convert, compact: true, busy: model.isBusy || model.isImporting, add: model.chooseFiles) { model.importURLs($0) }
        }
    }
}

struct MergeWorkspace: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(model.pdfs.count) PDFS · \(model.pdfs.reduce(0) { $0 + $1.pageCount }) PAGES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
                Spacer()
                Button { model.pdfs.reverse() } label: { Label("Reverse order", systemImage: "arrow.up.arrow.down").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.isBusy)
            }
            VStack(spacing: 10) {
                ForEach(Array(model.pdfs.enumerated()), id: \.element.id) { index, file in
                    MergeFileRow(model: model, file: file, index: index)
                }
            }
            Label("Drag to reorder. Drop another PDF onto a file to choose where it goes.", systemImage: "hand.draw").font(.system(size: 11)).foregroundStyle(.secondary)
            DropArea(mode: .merge, compact: true, busy: model.isBusy || model.isImporting, add: model.chooseFiles) { model.importURLs($0) }
        }
    }
}

struct MergeFileRow: View {
    @ObservedObject var model: AppModel
    let file: InputFile
    let index: Int
    @State private var targeted = false
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(String(format: "%02d", index + 1)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 20)
            FileThumbnail(file: file, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(file.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(file.detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            IconButton(symbol: "eye", help: "Preview PDF") { model.preview = PreviewItem(url: file.url) }
            Menu {
                Button("Move up") { if index > 0 { model.pdfs.swapAt(index, index - 1) } }.disabled(index == 0)
                Button("Move down") { if index + 1 < model.pdfs.count { model.pdfs.swapAt(index, index + 1) } }.disabled(index + 1 == model.pdfs.count)
            } label: { Image(systemName: "ellipsis").frame(width: 20) }.menuStyle(.borderlessButton).frame(width: 26).disabled(model.isBusy)
            IconButton(symbol: "xmark", help: "Remove PDF") { model.pdfs.removeAll { $0.id == file.id } }.disabled(model.isBusy)
        }.padding(13)
            .background(targeted ? Palette.blue.opacity(0.07) : Color.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? Palette.blue.opacity(0.6) : Palette.line, lineWidth: 1))
            .onDrag { model.isBusy ? NSItemProvider() : NSItemProvider(object: "fold-pdf:\(file.id.uuidString)" as NSString) }
            .onDrop(of: [.fileURL, .plainText], isTargeted: $targeted) { providers in
                guard !model.isBusy, !model.isImporting else { return false }
                if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
                    readDroppedURLs(providers) { urls in
                        guard !urls.isEmpty else { return }
                        model.mergeDrop = MergeDrop(urls: urls, target: file.id, targetName: file.url.lastPathComponent)
                    }
                } else {
                    readDragID(providers, prefix: "fold-pdf:") { model.movePDF($0, to: file.id) }
                }
                return true
            }
    }
}

struct PagesWorkspace: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(model.selectedPages.isEmpty ? "\(model.pages.count) pages" : "\(model.selectedPages.count) selected").font(.system(size: 12, weight: .medium)).frame(minWidth: 78, alignment: .leading)
                Button(model.selectedPages.count == model.pages.count ? "Deselect" : "Select all") { model.selectedPages = model.selectedPages.count == model.pages.count ? [] : Set(model.pages.map(\.id)) }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.blue)
                Spacer()
                IconButton(symbol: "arrow.uturn.backward", help: "Undo page edit (⌘Z)") { model.undoPages() }.disabled(model.pageHistory.isEmpty)
                Divider().frame(height: 18)
                IconButton(symbol: "rotate.right", help: "Rotate selected pages") { model.rotatePages() }.disabled(model.selectedPages.isEmpty)
                IconButton(symbol: "trash", help: "Remove selected pages") { model.removePages() }.disabled(model.selectedPages.isEmpty)
                Button("Extract…") { model.run(extract: true) }.controlSize(.small).disabled(model.selectedPages.isEmpty)
            }.disabled(model.isBusy)
            HStack(spacing: 8) {
                Text("Select a range").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("e.g. 1–3, 5", text: $model.rangeText).textFieldStyle(.roundedBorder).frame(width: 120).onSubmit { model.selectRange() }
                Button("Select") { model.selectRange() }.controlSize(.small).disabled(model.rangeText.isEmpty)
                Spacer()
                Text("Drag pages to reorder").font(.system(size: 11)).foregroundStyle(.tertiary)
            }.disabled(model.isBusy)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 18)], spacing: 22) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                    PageTile(model: model, page: page, index: index)
                }
            }
            DropArea(mode: .pages, compact: true, busy: model.isBusy || model.isImporting, add: model.chooseFiles) { model.importURLs($0) }
        }
    }
}

struct PageTile: View {
    @ObservedObject var model: AppModel
    let page: PageItem
    let index: Int
    @State private var targeted = false
    var selected: Bool { model.selectedPages.contains(page.id) }
    var body: some View {
        Button {
            if selected { model.selectedPages.remove(page.id) } else { model.selectedPages.insert(page.id) }
        } label: {
            VStack(spacing: 9) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035))
                    if let image = page.thumbnail {
                        GeometryReader { geometry in
                            let sideways = page.reference.rotation % 180 != 0
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                                .frame(width: sideways ? geometry.size.height : geometry.size.width,
                                       height: sideways ? geometry.size.width : geometry.size.height)
                                .rotationEffect(.degrees(Double(page.reference.rotation)))
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        }.padding(12)
                    }
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17)).foregroundStyle(selected ? Palette.blue : Color.secondary.opacity(0.4))
                        .background(Palette.canvas, in: Circle()).padding(8)
                }.frame(height: 178)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected || targeted ? Palette.blue : Palette.line, lineWidth: selected || targeted ? 2 : 1))
                HStack(spacing: 4) {
                    Text("\(index + 1)").font(.system(size: 11, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? Palette.blue : .secondary)
                    if page.reference.rotation != 0 { Image(systemName: "rotate.right").font(.system(size: 9)).foregroundStyle(.tertiary) }
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(model.isBusy)
            .accessibilityLabel("Page \(index + 1) from \(page.reference.source.lastPathComponent)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .onDrag { model.isBusy ? NSItemProvider() : NSItemProvider(object: "fold-page:\(page.id.uuidString)" as NSString) }
            .onDrop(of: [.plainText], isTargeted: $targeted) { providers in
                guard !model.isBusy else { return false }
                readDragID(providers, prefix: "fold-page:") { model.movePage($0, to: page.id) }; return true
            }
            .contextMenu {
                Button("Preview source PDF") { model.preview = PreviewItem(url: page.reference.source) }
                Button("Move left") { if index > 0 { model.movePage(page.id, to: model.pages[index - 1].id) } }.disabled(index == 0 || model.isBusy)
                Button("Move right") { if index + 1 < model.pages.count { model.movePage(page.id, to: model.pages[index + 1].id) } }.disabled(index + 1 == model.pages.count || model.isBusy)
            }
    }
}

private func readDragID(_ providers: [NSItemProvider], prefix: String, completion: @escaping (UUID) -> Void) {
    guard let provider = providers.first else { return }
    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
        guard let value = object as? String, value.hasPrefix(prefix), let id = UUID(uuidString: String(value.dropFirst(prefix.count))) else { return }
        Task { @MainActor in completion(id) }
    }
}

struct ExportBar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            if model.isBusy {
                HStack { ProgressView(value: model.progress).progressViewStyle(.linear); Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            if model.workspace != .convert {
                HStack(spacing: 10) {
                    Text("Save as").foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                    TextField("Document name", text: $model.outputName).textFieldStyle(.plain)
                    Text(".pdf").foregroundStyle(.tertiary)
                }.font(.system(size: 12)).padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7)).disabled(model.isBusy)
            }
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SAVE TO").font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.tertiary)
                    Menu {
                        Button("Same folder as original") { model.destination = nil }
                        Button("Choose folder…") { model.chooseDestination() }
                    } label: {
                        Label(model.destination?.lastPathComponent ?? "Same folder as original", systemImage: "folder").font(.system(size: 12)).lineLimit(1)
                    }.menuStyle(.borderlessButton).fixedSize().disabled(model.isBusy)
                }
                if model.workspace == .convert {
                    Rectangle().fill(Palette.line).frame(width: 1, height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("QUALITY").font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.tertiary)
                        Picker("Quality", selection: $model.quality) { ForEach(ExportQuality.allCases) { value in Text(value.rawValue).tag(value) } }
                            .labelsHidden().pickerStyle(.menu).frame(width: 132).disabled(model.isBusy)
                    }
                }
                Spacer(minLength: 0)
                if model.isBusy { Button("Cancel") { model.cancel() }.buttonStyle(QuietButtonStyle()) }
                else {
                    Button { model.run() } label: { HStack(spacing: 8) { Text(actionTitle); Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)) } }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!model.canRun)
                }
            }
        }.padding(.horizontal, 30).padding(.vertical, 18)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 0.5) }
    }
    var actionTitle: String {
        switch model.workspace {
        case .convert: return "Convert \(model.files.filter { $0.output == nil }.count) \(model.files.filter { $0.output == nil }.count == 1 ? "file" : "files")"
        case .merge: return "Merge PDFs"
        case .pages: return "Save PDF"
        case .recent: return "Export"
        }
    }
}
