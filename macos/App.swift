import AppKit
import PDFKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openPanel: NSOpenPanel?
    private var pendingOpens = 0
    private var receivedLaunchFiles = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also set the running application's icon for Dock and Cmd+Tab when
        // Launch Services has not yet registered this locally built bundle.
        if let icon = NanoIcons.application() {
            NSApp.applicationIconImage = icon
        }
        buildMenus()
        NSApp.activate(ignoringOtherApps: true)
        // Let Finder's launch-time open event arrive before offering a picker.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.receivedLaunchFiles, self.pendingOpens == 0,
                  NSDocumentController.shared.documents.isEmpty else { return }
            self.chooseDocument(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        receivedLaunchFiles = true
        openPanel?.cancel(nil)
        openDocuments(at: urls)
    }

    @objc private func chooseDocument(_ sender: Any?) {
        if let openPanel { openPanel.makeKeyAndOrderFront(nil); return }
        guard pendingOpens == 0 else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        openPanel = panel
        panel.begin { [weak self] response in
            guard let self else { return }
            if self.openPanel === panel { self.openPanel = nil }
            guard response == .OK else { return }
            self.openDocuments(at: panel.urls)
        }
    }

    private func openDocuments(at urls: [URL]) {
        pendingOpens += urls.count
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
                DispatchQueue.main.async {
                    self?.pendingOpens -= 1
                    if let error { NSApp.presentError(error) }
                }
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    // Keep the app available in the Dock after the last document closes.
    // Cancelling the picker leaves the app running without an empty reader.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { chooseDocument(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { CodexAccount.shared.shutdown() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DispatchQueue.main.async {
            NSDocumentController.shared.closeAllDocuments(withDelegate: self, didCloseAllSelector: #selector(self.documentsClosed(_:didCloseAll:contextInfo:)), contextInfo: nil)
        }
        return .terminateLater
    }

    @objc private func documentsClosed(_ controller: NSDocumentController, didCloseAll: Bool, contextInfo: UnsafeMutableRawPointer?) {
        NSApp.reply(toApplicationShouldTerminate: didCloseAll)
    }

    private func buildMenus() {
        let bar = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let root = NSMenuItem(); let submenu = NSMenu(title: title)
            root.submenu = submenu; bar.addItem(root); return submenu
        }
        func item(_ menu: NSMenu, _ title: String, _ selector: Selector?, _ key: String = "", target: AnyObject? = nil) {
            let entry = menu.addItem(withTitle: title, action: selector, keyEquivalent: key); entry.target = target
        }
        let app = menu("PDF Nano")
        item(app, "About PDF Nano", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        app.addItem(.separator())
        item(app, "Hide PDF Nano", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        item(app, "Quit PDF Nano", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = menu("File")
        item(file, "New Tab", #selector(NSDocumentController.newDocument(_:)), "t", target: NSDocumentController.shared)
        item(file, "Open…", #selector(chooseDocument(_:)), "o", target: self)
        item(file, "Scan Images to PDF…", #selector(ReaderController.scanImages))
        file.addItem(.separator())
        item(file, "Save", #selector(NSDocument.save(_:)), "s")
        item(file, "Save As…", #selector(NSDocument.saveAs(_:)), "S")
        item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        let edit = menu("Edit")
        item(edit, "Undo", Selector(("undo:")), "z")
        item(edit, "Redo", Selector(("redo:")), "Z")
        edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        let view = menu("View")
        item(view, "Find…", #selector(ReaderController.focusSearch), "f")
        item(view, "Find Next", #selector(ReaderController.nextSearchResult), "g")
        item(view, "Toggle Thumbnails", #selector(ReaderController.togglePages), "1")
        item(view, "Toggle Night Mode", #selector(ReaderController.toggleNightMode))
        item(view, "Zoom In", #selector(ReaderController.zoomIn), "+")
        item(view, "Zoom Out", #selector(ReaderController.zoomOut), "-")
        item(view, "Fit Page", #selector(ReaderController.fitPage), "0")
        view.addItem(.separator())
        item(view, "Recognize Page Text", #selector(ReaderController.recognizeText))
        item(view, "Toggle Agent", #selector(ReaderController.toggleAgent), "2")
        let window = menu("Window")
        item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        item(window, "Show Tab Bar", #selector(NSWindow.toggleTabBar(_:)))
        item(window, "Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "}")
        item(window, "Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "{")
        item(window, "Merge All Windows", #selector(NSWindow.mergeAllWindows(_:)))
        NSApp.windowsMenu = window
        NSApp.mainMenu = bar
    }
}
