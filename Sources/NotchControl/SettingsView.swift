import AppKit
import NotchControlCore
import NotchControlUI
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @State private var provider = AgentProvider.claude
    @State private var configPath: String?
    @State private var planPath: String?
    @State private var busy = false
    private var m: Messages { store.messages }
    var body: some View {
        Form {
            Section(m.text("position")) {
                Picker(m.text("edge"), selection: $store.preferences.edge) { Text(m.text("left")).tag(PanelEdge.left); Text(m.text("right")).tag(PanelEdge.right) }
                Picker(m.text("display"), selection: Binding(get: { store.preferences.screenID ?? screenID(store.screen) }, set: { store.preferences.screenID = $0 })) {
                    ForEach(NSScreen.screens, id: \.localizedName) { screen in Text(screen.localizedName).tag(screenID(screen)) }
                }
                Slider(value: $store.preferences.railPosition, in: 0...1) { Text(m.text("position")) }
                Slider(value: $store.preferences.panelWidth, in: 360...max(360, store.screen.visibleFrame.width * 0.8)) { Text(m.text("width")) }
                Toggle(m.text("always_visible"), isOn: $store.preferences.alwaysVisible)
            }
            Section(m.text("report")) {
                fileRow(store.preferences.workPath, key: "choose_work", history: false)
                fileRow(store.preferences.historyPath, key: "choose_history", history: true)
            }
            Section(m.text("waiting")) { alertSettings($store.preferences.waiting) }
            Section(m.text("completed")) { alertSettings($store.preferences.completed) }
            Section(m.text("settings")) {
                Picker(m.text("language"), selection: $store.preferences.language) { Text("Português (Brasil)").tag(InterfaceLanguage.portuguese); Text("English").tag(InterfaceLanguage.english) }
                Toggle(m.text("start_login"), isOn: Binding(get: { store.preferences.startAtLogin }, set: { store.setLogin($0) }))
            }
            Section(m.text("integration")) {
                if let setup = store.setup {
                    capability("iTerm2", available: setup.itermInstalled, recovery: "install_iterm")
                    capability(m.text("api"), available: setup.apiEnabled == true, recovery: "enable_api")
                    capability("SDK iTerm2 2.25", available: setup.sdkVersion == "2.25", recovery: "sdk_missing")
                    capability("Claude Code", available: setup.providers["claude"] == true, recovery: "install_cli")
                    capability("Codex CLI", available: setup.providers["codex"] == true, recovery: "install_cli")
                    capability("Cursor Agent", available: setup.providers["cursor"] == true, recovery: "install_cli")
                }
                Text(m.text(store.gateway.statusCode)).fixedSize(horizontal: false, vertical: true)
                HStack { Button(m.text("diagnostics")) { store.diagnose(); store.gateway.refresh() }.disabled(store.diagnosing); Button(m.text("reconnect"), action: store.reconnect) }
                Picker(m.text("hooks"), selection: $provider) { Text("Claude Code").tag(AgentProvider.claude); Text("Codex CLI").tag(AgentProvider.codex) }
                Text(m.text("hook_trust")).font(.caption).foregroundStyle(DesignTokens.muted)
                if let configPath { Text(configPath).font(.caption).textSelection(.enabled) }
                HStack {
                    Button(m.text("prepare_hooks"), action: prepareHooks).disabled(busy)
                    Button(m.text("install_hooks")) { applyHooks(remove: false) }.disabled(busy || planPath == nil)
                    Button(m.text("remove_hooks")) { applyHooks(remove: true) }.disabled(busy || planPath == nil)
                }
                if busy { ProgressView().controlSize(.small).frame(height: 18) }
            }
            if let notice = store.noticeKey { Text(m.text(notice)).foregroundStyle(DesignTokens.muted) }
        }.formStyle(.grouped).preferredColorScheme(.dark)
            .onChange(of: store.preferences.edge) { _, _ in store.persistPreferences() }
            .onChange(of: store.preferences.screenID) { _, _ in store.persistPreferences() }
            .onChange(of: store.preferences.railPosition) { _, _ in store.persistPreferences() }
            .onChange(of: store.preferences.panelWidth) { _, _ in store.persistPreferences() }
            .onChange(of: store.preferences.alwaysVisible) { _, _ in store.persistPreferences() }
            .onChange(of: store.preferences.language) { _, _ in store.persistPreferences() }
            .onChange(of: store.preferences.waiting) { _, _ in store.persistPreferences() }
            .onChange(of: store.preferences.completed) { _, _ in store.persistPreferences() }
            .onChange(of: provider) { _, _ in planPath = nil; configPath = nil }
    }
    private func capability(_ label: String, available: Bool, recovery: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.compact) {
            Label(label, systemImage: available ? "checkmark.circle" : "exclamationmark.circle")
            if !available { Text(m.text(recovery)).font(.caption).foregroundStyle(DesignTokens.muted) }
        }
    }
    private func screenID(_ screen: NSScreen) -> UInt32 { (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
    private func fileRow(_ path: String?, key: String, history: Bool) -> some View {
        HStack { Text(path ?? m.text("missing_report")).font(.caption).lineLimit(2); Spacer(); Button(m.text(key)) { store.chooseFile(history: history) } }
    }
    private func alertSettings(_ setting: Binding<AlertPreference>) -> some View {
        VStack {
            Toggle(m.text("notification"), isOn: setting.notification)
            Toggle(m.text("sound"), isOn: setting.sound)
            HStack {
                Picker(m.text("sound"), selection: setting.soundName) { ForEach(["Glass", "Ping", "Pop", "Basso", "Submarine"], id: \.self) { Text($0).tag($0) } }
                Button(m.text("preview")) { NSSound(named: NSSound.Name(setting.wrappedValue.soundName))?.play() }
            }
        }
    }
    private func prepareHooks() {
        let dialog = NSOpenPanel(); dialog.canChooseFiles = true; dialog.canChooseDirectories = true; dialog.showsHiddenFiles = true
        dialog.message = m.text("prepare_hooks")
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        let target = url.hasDirectoryPath ? url.appendingPathComponent(provider == .claude ? "settings.json" : "hooks.json") : url
        configPath = target.path
        let plan = store.project.appendingPathComponent(".notchcontrol/hook-plan-\(provider.rawValue).json").path
        run(["prepare", "--provider", provider.rawValue, "--config", target.path, "--plan", plan]) { successful in
            planPath = successful ? plan : nil
            store.noticeKey = successful ? "hooks_prepared" : "hooks_failed"
        }
    }
    private func applyHooks(remove: Bool) {
        guard let planPath else { return }
        run([remove ? "remove" : "apply", "--plan", planPath]) { successful in
            store.noticeKey = successful ? (remove ? "hooks_removed" : "hooks_installed") : "hooks_failed"
            self.planPath = nil
        }
    }
    private func run(_ arguments: [String], completion: @escaping (Bool) -> Void) {
        busy = true
        let root = store.project
        Task { @MainActor in
            let result = await Task.detached {
                let process = Process(); process.executableURL = root.appendingPathComponent(".venv/bin/python3")
                process.arguments = [root.appendingPathComponent("scripts/configure-hooks.py").path] + arguments
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
            }.value
            busy = false; completion(result)
        }
    }
}
