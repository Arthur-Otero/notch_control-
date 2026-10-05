import NotchControlUI
import AppKit
import SwiftUI

@MainActor
final class ProofDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var controller: TerminalGateway?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let path: String
        if let index = args.firstIndex(of: "--project"), args.indices.contains(index + 1) {
            path = args[index + 1]
        } else {
            path = FileManager.default.currentDirectoryPath
        }
        let controller = TerminalGateway(project: URL(fileURLWithPath: path))
        self.controller = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "NotchControl — Prova da integração"
        window.minSize = NSSize(width: 750, height: 400)
        window.contentView = NSHostingView(rootView: ProofView(controller: controller))
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller, controller.isRunning else { return .terminateNow }
        controller.shutdown { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

let app = NSApplication.shared
let delegate = ProofDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
let menu = NSMenu()
let appItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Sair da prova", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
menu.addItem(appItem)
let editItem = NSMenuItem(title: "Editar", action: nil, keyEquivalent: "")
let editMenu = NSMenu(title: "Editar")
editMenu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editItem.submenu = editMenu
menu.addItem(editItem)
let windowItem = NSMenuItem(title: "Janela", action: nil, keyEquivalent: "")
let windowMenu = NSMenu(title: "Janela")
windowMenu.addItem(withTitle: "Fechar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
windowItem.submenu = windowMenu
menu.addItem(windowItem)
app.mainMenu = menu
app.run()
