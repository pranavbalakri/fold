import AppKit
import SwiftUI
import Carbon
import FoldCore

@main
enum FoldApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem?
    var quickPanel: NSPanel?
    var quickModel: AppModel?
    let model = AppModel.shared
    let shortcut = FinderShortcut()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        NSApp.appearance = model.appearance == "light" ? NSAppearance(named: .aqua) : model.appearance == "dark" ? NSAppearance(named: .darkAqua) : nil
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Fold"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 900, height: 680)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.center()
        window.setFrameAutosaveName("FoldMainWindow")
        showWindow()
        NSApplication.shared.servicesProvider = self
        NSUpdateDynamicServices()
        setupStatusItem()
        configureShortcut()
        NotificationCenter.default.addObserver(self, selector: #selector(configureShortcut), name: .foldShortcutChanged, object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isBusy || quickModel?.isBusy == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop the current export?"
        alert.informativeText = "Finished files will be kept. Your originals won’t change."
        alert.addButton(withTitle: "Keep working"); alert.addButton(withTitle: "Stop and quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        let tasks = [model.workTask, quickModel?.workTask].compactMap { $0 }
        model.cancel(); quickModel?.cancel()
        Task { for task in tasks { await task.value }; sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func application(_ sender: NSApplication, open urls: [URL]) { showWindow(); model.importURLs(urls) }

    @objc func showWindow() { quickPanel?.orderOut(nil); model.reloadHistory(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func addFiles() { showWindow(); model.chooseFiles() }
    @objc func settings() { showWindow(); model.showingSettings = true }
    @objc func help() { showWindow(); model.showingHelp = true }
    @objc func undo() {
        if let editor = window.firstResponder as? NSTextView { editor.undoManager?.undo() }
        else if !model.isBusy { model.undoPages() }
    }
    @objc func startExport() { model.run() }
    @objc func pasteFiles() {
        let urls = Self.fileURLs(from: .general)
        if !urls.isEmpty { showWindow(); model.importURLs(urls) }
    }

    @objc func receiveFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = Self.fileURLs(from: pasteboard)
        guard !urls.isEmpty else { error.pointee = "Select one or more files in Finder."; return }
        presentQuickPanel(urls: urls, mode: Workspace(rawValue: userData ?? "convert"))
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { return urls }
        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] { return paths.map { URL(fileURLWithPath: $0) } }
        return []
    }

    @objc func configureShortcut() {
        shortcut.unregister()
        if model.shortcutEnabled {
            model.shortcutRegistered = shortcut.register { [weak self] in self?.takeFinderSelection() }
        } else { model.shortcutRegistered = false }
    }

    @objc func takeFinderSelection() {
        // Read only the explicit Finder selection. This runs only after a user invokes the shortcut/menu.
        Task {
            let result = await Task.detached { () -> ([URL], String?) in
                let source = """
                tell application "Finder"
                    set selectedPaths to {}
                    repeat with selectedItem in (get selection)
                        set end of selectedPaths to POSIX path of (selectedItem as alias)
                    end repeat
                    return selectedPaths
                end tell
                """
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else { return ([], "Couldn’t read your Finder selection.") }
                let result = script.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int
                    return ([], code == -1743 ? "Allow Fold to access Finder in System Settings → Privacy & Security → Automation. You can also drag files into Fold or use Finder’s Services menu." : "Couldn’t read your Finder selection. Try dragging your files into Fold.")
                }
                var urls: [URL] = []
                if result.numberOfItems > 0 {
                    for index in 1...result.numberOfItems { if let path = result.atIndex(index)?.stringValue { urls.append(URL(fileURLWithPath: path)) } }
                }
                return (urls, nil)
            }.value
            if let error = result.1 { showWindow(); model.issue = UserIssue(title: "Connect to Finder", message: error) }
            else if result.0.isEmpty { showWindow(); model.completion = "Select files in Finder, then press ⌃⌥Space." }
            else { presentQuickPanel(urls: result.0, mode: .convert) }
        }
    }

    func presentQuickPanel(urls: [URL], mode: Workspace?) {
        if let quickModel, quickModel.isBusy || quickModel.isImporting {
            quickPanel?.makeKeyAndOrderFront(nil)
            quickModel.issue = UserIssue(title: "One moment", message: "Wait for the current quick export to finish before starting another.")
            return
        }
        let session = AppModel()
        quickModel = session
        session.importURLs(urls, mode: mode)
        if quickPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 510, height: 510), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Fold"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true; panel.level = .floating
            quickPanel = panel
        }
        quickPanel?.contentView = NSHostingView(rootView: QuickPanelView(model: session, resize: { [weak self] height in
            self?.quickPanel?.setContentSize(NSSize(width: 510, height: height))
        }, openWorkspace: { [weak self, weak session] in
            guard let self, let session else { return }
            guard !self.model.isBusy, !self.model.isImporting else {
                session.issue = UserIssue(title: "The workspace is busy", message: "Let the current workspace export finish first.")
                return
            }
            self.model.workspace = session.workspace
            self.model.files.append(contentsOf: session.files.filter { file in !self.model.files.contains { $0.url == file.url } })
            self.model.pdfs.append(contentsOf: session.pdfs.filter { file in !self.model.pdfs.contains { $0.url == file.url } })
            if !session.pages.isEmpty { self.model.rememberPages(); self.model.pages.append(contentsOf: session.pages); self.model.outputName = session.outputName }
            self.showWindow()
        }))
        quickPanel?.center(); quickPanel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Fold")
        let menu = NSMenu()
        menu.addItem(menuItem("Open Fold", #selector(showWindow), ""))
        menu.addItem(menuItem("Use Finder Selection", #selector(takeFinderSelection), ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(settings), ""))
        menu.addItem(NSMenuItem(title: "Quit Fold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        item.menu = menu; statusItem = item
    }

    func menuItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(menuItem("About Fold", #selector(help), ""))
        appMenu.addItem(menuItem("Settings…", #selector(settings), ","))
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(); appMenu.addItem(services); NSApp.servicesMenu = services.submenu
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Fold", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Quit Fold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu; menu.addItem(appItem)
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(menuItem("Add Files…", #selector(addFiles), "o"))
        fileMenu.addItem(menuItem("Export", #selector(startExport), "\r"))
        fileMenu.addItem(menuItem("Paste Files", #selector(pasteFiles), "V"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        file.submenu = fileMenu; menu.addItem(file)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(menuItem("Undo", #selector(undo), "z"))
        editMenu.addItem(.separator())
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        edit.submenu = editMenu; menu.addItem(edit)
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""); let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(menuItem("Show Fold", #selector(showWindow), "")); windowItem.submenu = windowMenu
        menu.addItem(windowItem); NSApp.windowsMenu = windowMenu
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: ""); let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(menuItem("Using Fold with Finder", #selector(help), "?")); helpItem.submenu = helpMenu; menu.addItem(helpItem)
        NSApp.mainMenu = menu
    }
}

@MainActor
final class FinderShortcut {
    var reference: EventHotKeyRef?
    var handler: EventHandlerRef?
    var action: (() -> Void)?
    func register(action: @escaping () -> Void) -> Bool {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<FinderShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action?() }
            return noErr
        }, 1, &event, pointer, &handler)
        let id = EventHotKeyID(signature: 0x464F4C44, id: 1)
        return RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &reference) == noErr
    }
    func unregister() {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}
