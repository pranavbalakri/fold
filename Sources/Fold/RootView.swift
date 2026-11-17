import SwiftUI
import AppKit
import FoldCore

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var sidebarVisible = true
    @State private var rootTargeted = false
    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible { sidebar.frame(width: 202) }
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(Palette.line).frame(height: 0.5)
                if model.workspace == .recent { RecentView(model: model) }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            heading
                            if let completion = model.completion { completionBanner(completion) }
                            if model.currentCount == 0 {
                                if model.workspace == .pages && !model.pageHistory.isEmpty {
                                    HStack { Text("All pages removed.").foregroundStyle(.secondary); Spacer(); Button("Undo removal") { model.undoPages() }.buttonStyle(.plain).foregroundStyle(Palette.blue) }.font(.system(size: 12))
                                }
                                DropArea(mode: model.workspace, busy: model.isImporting, add: model.chooseFiles) { model.importURLs($0) }
                                if model.workspace == .convert { presets }
                                else { workflowNote }
                                finderTip
                            } else {
                                switch model.workspace {
                                case .convert: ConversionList(model: model)
                                case .merge: MergeWorkspace(model: model)
                                case .pages: PagesWorkspace(model: model)
                                case .recent: EmptyView()
                                }
                            }
                        }.padding(.horizontal, 34).padding(.top, 30).padding(.bottom, 28)
                    }
                    if model.currentCount > 0 { ExportBar(model: model) }
                }
                bottomBar
            }.background(Palette.canvas)
        }
        .background(MaterialView())
        .tint(Palette.blue)
        .font(.system(size: 13))
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            if model.isImporting {
                VStack(spacing: 12) { ProgressView().controlSize(.small); Text("Preparing your files…").font(.system(size: 12)) }
                    .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).shadow(color: .black.opacity(0.1), radius: 20)
            }
        }
        .alert(item: $model.issue) { issue in Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK"))) }
        .sheet(isPresented: $model.showingSettings) { SettingsView(model: model) }
        .sheet(isPresented: $model.showingHelp) { FinderHelpView() }
        .sheet(item: $model.mergeDrop) { drop in MergeOrderSheet(model: model, drop: drop) }
        .sheet(item: $model.preview) { item in
            VStack(spacing: 0) {
                HStack { Text(item.url.lastPathComponent).font(.headline); Spacer(); Button("Done") { model.preview = nil }.keyboardShortcut(.cancelAction) }.padding(18)
                Divider(); PDFPreview(url: item.url)
            }.frame(width: 650, height: 650)
        }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) { FoldMark(size: 31); Text("Fold").font(.system(size: 22, weight: .semibold, design: .rounded)).tracking(-0.5) }
                .padding(.horizontal, 23).padding(.top, 60).padding(.bottom, 38)
            Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.bottom, 10)
            VStack(spacing: 4) {
                ForEach([Workspace.convert, .merge, .pages]) { item in sidebarItem(item) }
            }.padding(.horizontal, 12)
            Text("LIBRARY").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 10)
            sidebarItem(.recent).padding(.horizontal, 12)
            Spacer(minLength: 28)
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    Image(systemName: "command").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Always within reach").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) { KeyCap(text: "⌃"); KeyCap(text: "⌥"); KeyCap(text: "space") }
                Text("Select in Finder. Make it Fold.").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10)).padding(14)
            Divider().padding(.horizontal, 18)
            HStack {
                Button { model.showingSettings = true } label: { Label("Settings", systemImage: "gearshape").font(.system(size: 12)) }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text("0.1").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 22).frame(height: 52)
        }.background(MaterialView()).overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 0.5) }
    }

    func sidebarItem(_ item: Workspace) -> some View {
        let selected = model.workspace == item
        return Button {
            model.workspace = item; model.completion = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol).font(.system(size: 15, weight: .medium)).frame(width: 22).foregroundStyle(selected ? Palette.blue : Color.secondary)
                Text(item.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
                if item == .recent && !model.recents.isEmpty { Text("\(model.recents.count)").font(.system(size: 10)).foregroundStyle(.tertiary) }
            }.padding(.horizontal, 10).frame(height: 36)
                .background(selected ? Palette.blue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(model.isBusy || model.isImporting)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var toolbar: some View {
        HStack(spacing: 12) {
            IconButton(symbol: "sidebar.left", help: "Toggle sidebar") { sidebarVisible.toggle() }
            Text(model.workspace.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if model.currentCount > 0 && model.workspace != .recent {
                Button("Clear") { model.clearWorkspace() }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.isBusy || model.isImporting)
                Rectangle().fill(Palette.line).frame(width: 1, height: 15).padding(.horizontal, 2)
            }
            if model.workspace != .recent { IconButton(symbol: "plus", help: "Add files (⌘O)") { model.chooseFiles() }.disabled(model.isBusy || model.isImporting) }
            IconButton(symbol: "questionmark.circle", help: "Using Fold") { model.showingHelp = true }
        }.padding(.leading, sidebarVisible ? 21 : 85).padding(.trailing, 22).frame(height: 54)
    }

    var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(model.workspace.title).font(.system(size: 28, weight: .semibold)).tracking(-0.65)
                Text(model.workspace.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) { Circle().fill(Color(red: 0.26, green: 0.64, blue: 0.46)).frame(width: 5, height: 5); Text("ON YOUR MAC").font(.system(size: 9, weight: .semibold)).tracking(0.8) }
                .foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 6)
                .background(Color.primary.opacity(0.035), in: Capsule()).padding(.top, 7)
        }
    }

    var presets: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("EVERYDAY SHORTCUTS").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
            HStack(spacing: 10) {
                PresetCard(symbol: "photo", title: "HEIC → PNG", caption: "Photos, made shareable", color: Palette.blue) { model.applyPreset(.png) }
                PresetCard(symbol: "play.rectangle", title: "Video → MP4", caption: "Plays almost anywhere", color: .purple) { model.applyPreset(.mp4) }
                PresetCard(symbol: "square.stack", title: "Merge PDFs", caption: "Better together", color: Color(red: 0.83, green: 0.39, blue: 0.31)) { model.workspace = .merge }
            }
        }
    }

    var workflowNote: some View {
        HStack(spacing: 22) {
            ForEach(Array((model.workspace == .merge ? [("1", "Add your PDFs"), ("2", "Set the order"), ("3", "Save as one")] : [("1", "Add a PDF"), ("2", "Make it yours"), ("3", "Save a copy")]).enumerated()), id: \.offset) { _, step in
                HStack(spacing: 8) {
                    Text(step.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).frame(width: 22, height: 22).background(Color.primary.opacity(0.045), in: Circle())
                    Text(step.1).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 7)
    }

    var finderTip: some View {
        HStack(spacing: 13) {
            Image(systemName: "cursorarrow.and.square.on.square.dashed").font(.system(size: 21, weight: .light)).foregroundStyle(.secondary).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("Right at home in Finder.").font(.system(size: 12, weight: .medium))
                Text("Select your files, then press ⌃⌥Space to get started.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { model.showingHelp = true } label: { HStack(spacing: 5) { Text("See how"); Image(systemName: "arrow.up.right").font(.system(size: 9)) }.font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }.padding(16).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }

    func completionBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: model.lastOutputs.isEmpty ? "info.circle" : "checkmark.circle.fill").foregroundStyle(model.lastOutputs.isEmpty ? Color.secondary : .green)
            Text(text).font(.system(size: 12, weight: .medium))
            Spacer()
            if !model.lastOutputs.isEmpty { Button("Show in Finder") { model.reveal(model.lastOutputs) }.buttonStyle(.plain).foregroundStyle(Palette.blue) }
            IconButton(symbol: "xmark", help: "Dismiss") { model.completion = nil }
        }.padding(.leading, 13).padding(.trailing, 6).padding(.vertical, 7)
            .background(Color.green.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
    }

    var bottomBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.shield").font(.system(size: 10))
            Text("On-device. Off the cloud.").font(.system(size: 10))
            Spacer()
            Text(model.isBusy ? model.status : model.currentCount > 0 && model.workspace != .recent ? "Originals stay untouched" : "A little less file friction.").font(.system(size: 10))
        }.foregroundStyle(.tertiary).padding(.horizontal, 24).frame(height: 32)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 0.5) }
    }
}

struct PresetCard: View {
    let symbol: String
    let title: String
    let caption: String
    let color: Color
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack { Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(color); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.tertiary) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(caption).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading).frame(height: 94)
                .background(Color.primary.opacity(hovering ? 0.035 : 0.012), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).onHover { hovering = $0 }
    }
}
