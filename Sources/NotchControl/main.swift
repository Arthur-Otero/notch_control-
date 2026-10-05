import AppKit
import Combine
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: AppStore!
    private var windows: WindowCoordinator!
    private var status: NSStatusItem!
    private var subscription: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let index = arguments.firstIndex(of: "--project")
        let root = index.flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            ?? Bundle.main.object(forInfoDictionaryKey: "NotchControlProject") as? String ?? FileManager.default.currentDirectoryPath
        store = AppStore(project: URL(fileURLWithPath: root)); windows = WindowCoordinator(store: store)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: "NotchControl")
        buildMenus()
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.buildMenus() }
        }
        windows.layout(); store.start()
        if !FileManager.default.fileExists(atPath: store.project.appendingPathComponent(".notchcontrol/preferences.json").path) { windows.showSettings() }
    }
    private func buildMenus() {
        let m = store.messages
        let menu = NSMenu()
        for (key, selector, shortcut) in [("open", #selector(openReport), ""), ("settings", #selector(settings), ","), ("diagnostics", #selector(diagnostics), ""), ("close", #selector(closePanel), "w"), ("quit", #selector(quit), "q")] {
            let item = NSMenuItem(title: m.text(key), action: selector, keyEquivalent: shortcut); item.target = self; menu.addItem(item)
        }
        status.menu = menu
        let main = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = menu.copy() as? NSMenu; main.addItem(appItem)
        let edit = NSMenu(); let editItem = NSMenuItem(title: m.text("edit"), action: nil, keyEquivalent: ""); editItem.submenu = edit
        for (key, selector, shortcut) in [("copy", #selector(NSText.copy(_:)), "c"), ("paste", #selector(NSText.paste(_:)), "v")] { edit.addItem(NSMenuItem(title: m.text(key), action: selector, keyEquivalent: shortcut)) }
        main.addItem(editItem); NSApp.mainMenu = main
    }
    @objc private func openReport() { if store.content == "report" { windows.activate() } else { store.choose("report") } }
    @objc private func settings() { windows.showSettings() }
    @objc private func diagnostics() { store.diagnose(); store.reconnect(); windows.showSettings() }
    @objc private func closePanel() { store.close() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.shutdown { NSApp.reply(toApplicationShouldTerminate: true) }; return .terminateLater
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
