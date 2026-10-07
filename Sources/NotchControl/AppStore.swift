import AppKit
import Combine
import NotchControlCore
import NotchControlUI
import ServiceManagement
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

@MainActor
final class AppStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var preferences: AppPreferences
    @Published private(set) var registry: AgentRegistry
    @Published var content: String?
    @Published private(set) var lastPanelContent: String?
    @Published private(set) var closingSnapshot: TerminalSnapshot?
    @Published var expandedRail = false
    /// Task titles beside the bubbles, opened from the tab on the notch's inner side.
    @Published var titlesOpen = false
    @Published var historyTab = false
    @Published var olderHistory = false
    @Published var noticeKey: String?
    @Published var resumePending = false
    @Published var choices: [String] = []
    @Published var renameID: String?
    @Published var renameValue = ""
    @Published var dragWidth: Double?
    @Published private(set) var draggingRail = false
    @Published private(set) var railDragOrigin: RailPoint?
    @Published private(set) var setup: SetupDiagnostic?
    @Published private(set) var diagnosing = false
    let gateway: TerminalGateway
    let work = ReportReader()
    let history = ReportReader()
    let project: URL
    var onLayout: (() -> Void)?
    var onActivate: (() -> Void)?
    var onSettings: (() -> Void)?
    /// Shows the balloon of a notch row by `RailRow.id`; nil hides it.
    var onTooltip: ((String?) -> Void)?
    private var subscriptions: Set<AnyCancellable> = []
    private var alerts = AlertTracker()
    private var retry: Task<Void, Never>?
    private var retries = 0
    private var stopping = false
    private var resizeTask: Task<Void, Never>?
    private var resumeTimeout: Task<Void, Never>?
    private var createdID: String?
    private var pendingRequest: ResumeRequest?
    private var resumeOrigin: String?
    private var notificationRequested = false
    private var lastResize: String?
    private var hoverSerial = 0
    private var jumpRequested = false
    private var railDrag: RailDrag?
    private var railDragStart: RailPoint?
    private var railDragStartX: Double = 0
    var messages: Messages { Messages(language: preferences.language) }
    var selected: AgentSession? { registry.sessions.first { $0.id == content } }
    var presentedContent: String? { content ?? lastPanelContent }
    var presentedSession: AgentSession? { registry.sessions.first { $0.id == presentedContent } }
    /// Work entries replace the session list only when the option is on and a work file is chosen.
    var workBoard: WorkBoard? {
        guard preferences.showsWorkEntries, preferences.workPath != nil else { return nil }
        return WorkBoard(entries: work.document.entries, sessions: registry.sessions)
    }
    /// Work mode groups open entries, open sessions outside the file, then entries without a terminal, each in file order.
    var railRows: [RailRow] {
        guard let board = workBoard else { return registry.sessions.map(RailRow.session) }
        let sessions = Dictionary(registry.sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var open: [RailRow] = [], closed: [RailRow] = []
        for item in board.items {
            if case .open(let id) = item.mark, let session = sessions[id] { open.append(.entry(item, session)) }
            else { closed.append(.entry(item, nil)) }
        }
        let unlisted = board.unlisted.compactMap { sessions[$0] }.map(RailRow.session)
        let groups = [open, unlisted, closed].filter { !$0.isEmpty }
        return groups.enumerated().flatMap { index, rows in index == 0 ? rows : [.divider(index)] + rows }
    }
    var railCounts: (cells: Int, dividers: Int) {
        let rows = railRows
        let dividers = rows.filter { if case .divider = $0 { true } else { false } }.count
        return (rows.count - dividers, dividers)
    }
    /// Context share of the session's own terminal generation, if its status bar reports it.
    func contextPercent(_ session: AgentSession) -> Double? {
        gateway.contextUsage[session.terminal.id].flatMap { $0.terminal == session.terminal ? $0.usedPercent : nil }
    }
    /// Expanded rail window: the inner tab, the titles when open, and the bubble column.
    var railWindowWidth: CGFloat { NotchMetrics.tabDepth + DesignTokens.railWidth + (titlesOpen ? NotchMetrics.titlesWidth : 0) }
    func railFrameWidth(expanded: Bool) -> CGFloat { expanded ? railWindowWidth : DesignTokens.pillWidth }
    func toggleTitles() { titlesOpen.toggle(); onTooltip?(nil); onLayout?() }
    /// Pinned, the notch stays open whatever the visibility says; unpinned, the visibility decides when it folds.
    func togglePin() { preferences.alwaysVisible.toggle(); persistPreferences() }
    func setNotchVisibility(_ visibility: NotchVisibility) { preferences.notchVisibility = visibility; persistPreferences() }
    func railHeight(available: CGFloat) -> CGFloat {
        let counts = railCounts
        return NotchMetrics.height(sessions: counts.cells, dividers: counts.dividers, available: available, pin: preferences.showsPin)
    }
    var panelOpen: Bool { content != nil }
    /// Open while pinned, hovered, showing the panel or held by the visibility mode; otherwise the pill, whose arrow carries the sessions' state.
    var railExpanded: Bool {
        panelOpen || expandedRail || preferences.pinHoldsOpen || preferences.notchVisibility.holdsOpen(attention: registry.attention)
    }
    var screen: NSScreen {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == preferences.screenID }
        ?? NSScreen.main ?? NSScreen.screens[0]
    }

    init(project: URL) {
        self.project = project
        let folder = project.appendingPathComponent(".notchcontrol")
        preferences = AppPreferences.load(try? Data(contentsOf: folder.appendingPathComponent("preferences.json")))
        registry = (try? JSONDecoder().decode(AgentRegistry.self, from: Data(contentsOf: folder.appendingPathComponent("sessions.json")))) ?? AgentRegistry()
        gateway = TerminalGateway(project: project, privateSocket: true)
        super.init()
        registry.invalidateEvidence()
        work.open(preferences.workPath); history.open(preferences.historyPath)
        gateway.onEvidence = { [weak self] event, baseline in self?.accept(event, baseline: baseline) }
        gateway.onHistory = { [weak self] in
            guard self?.olderHistory == false, self?.jumpRequested == true else { return }
            self?.jumpRequested = false
            DispatchQueue.main.async { NotificationCenter.default.post(name: .notchControlJumpToEnd, object: nil) }
        }
        gateway.onResume = { [weak self] terminal, ambiguous in
            guard let self else { return }
            if let terminal { self.createdID = terminal; self.gateway.refresh() }
            else {
                self.resumePending = ambiguous; self.noticeKey = ambiguous ? "resume_uncertain" : "resume_failed"
                if !ambiguous { self.pendingRequest = nil; self.resumeTimeout?.cancel() }
            }
        }
        gateway.$terminals.dropFirst().sink { [weak self] terminals in
            guard let self, self.gateway.connected else { return }
            let candidates = terminals.compactMap { row -> AgentCandidate? in
                guard row.local, row.identityConfirmed, let name = row.provider, let provider = AgentProvider(rawValue: name) else { return nil }
                return AgentCandidate(terminal: row.identity, provider: provider, project: row.project, name: row.name, conversation: row.conversation)
            }
            self.registry.reconcile(candidates)
            for session in self.registry.sessions {
                _ = self.alerts.observe(id: session.id, state: session.state, sequence: session.sequence, kind: .unavailable, baseline: true)
            }
            if let selected = self.content, selected != "report", !self.registry.sessions.contains(where: { $0.id == selected }) {
                self.noticeKey = "session_closed"; self.gateway.closeMirror()
            }
            self.resolvePendingResume()
            self.save(); self.onLayout?()
        }.store(in: &subscriptions)
        gateway.$connected.dropFirst().sink { [weak self] connected in
            guard let self else { return }
            if connected { self.retries = 0; self.retry?.cancel() }
            else {
                self.registry.invalidateEvidence(); self.alerts.reset()
                self.createdID = nil
                if self.resumePending { self.noticeKey = "resume_uncertain" }
            }
        }.store(in: &subscriptions)
        gateway.$isRunning.dropFirst().sink { [weak self] running in
            guard let self, !running, !self.stopping else { return }
            self.retries += 1
            self.scheduleHelperStart(after: ReconnectPolicy.delay(afterFailures: self.retries))
        }.store(in: &subscriptions)
        // The helper cannot connect while iTerm2 is closed; reconnect as soon as it opens instead of waiting out the backoff.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification).sink { [weak self] note in
            let launched = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard launched?.bundleIdentifier == "com.googlecode.iterm2", let self, !self.stopping, !self.gateway.connected else { return }
            self.retries = 0
            // iTerm2 needs a moment to open its API; a failed first attempt falls back to the normal backoff.
            self.scheduleHelperStart(after: ReconnectPolicy.delay(afterFailures: 1))
        }.store(in: &subscriptions)
        gateway.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        work.$document.dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
            DispatchQueue.main.async { self?.onLayout?() }
        }.store(in: &subscriptions)
        gateway.$docked.dropFirst().sink { [weak self] _ in self?.onLayout?() }.store(in: &subscriptions)
        gateway.$dockFailed.dropFirst().sink { [weak self] _ in self?.onLayout?() }.store(in: &subscriptions)
        gateway.$snapshot.dropFirst().sink { [weak self] snapshot in
            guard let self, snapshot != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.coalesceResize() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            guard let self else { return }
            self.onLayout?()
        }.store(in: &subscriptions)
        if Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func start() { gateway.start(); diagnose() }
    func diagnose() {
        guard !diagnosing else { return }
        diagnosing = true
        let root = project
        Task { @MainActor [weak self] in
            let data = await Task.detached {
                let process = Process(); let pipe = Pipe()
                process.executableURL = root.appendingPathComponent(".venv/bin/python3")
                process.arguments = [root.appendingPathComponent("scripts/diagnose.py").path, "--root", root.path]
                process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
                do { try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); return data }
                catch { return Data() }
            }.value
            self?.setup = try? JSONDecoder().decode(SetupDiagnostic.self, from: data)
            self?.diagnosing = false
        }
    }
    func reconnect() { retries = 0; retry?.cancel(); gateway.refresh(); gateway.start() }
    private func scheduleHelperStart(after delay: TimeInterval) {
        retry?.cancel()
        retry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, self?.stopping == false else { return }
            self?.gateway.start()
        }
    }
    func persistPreferences() { preferences.normalize(); save(); onLayout?(); coalesceResize() }
    func choose(_ id: String) {
        onTooltip?(nil); choices = []
        if id != "report" {
            if panelOpen { close() }
            if let row = registry.sessions.first(where: { $0.id == id }), let terminal = gateway.terminals.first(where: { $0.identity == row.terminal }) {
                markSeen(id)
                gateway.reveal(terminal)
            } else { noticeKey = "session_closed" }
            return
        }
        if content == id { close(); return }
        gateway.embedOnSelect = false
        gateway.closeMirror(); jumpRequested = false; olderHistory = false; lastResize = nil; closingSnapshot = nil
        content = id; lastPanelContent = id; noticeKey = nil
        historyTab = false
        onLayout?(); onActivate?()
    }
    /// An open entry brings its terminal forward, a closed one resumes its newest session, a note opens the work file.
    func choose(_ item: WorkItem) {
        switch item.mark {
        case .open(let id): choose(id)
        case .closed(let request): onTooltip?(nil); resume(request)
        case .note:
            if content == "report" { onTooltip?(nil); historyTab = false; onActivate?() } else { choose("report") }
        }
    }
    func showOlderHistory() { jumpRequested = false; olderHistory = true; gateway.loadOlderHistory() }
    func jumpToEnd() {
        olderHistory = false; jumpRequested = true; gateway.loadHistory()
        NotificationCenter.default.post(name: .notchControlJumpToEnd, object: nil)
    }
    func sendText(_ text: String) { if olderHistory { jumpToEnd() }; gateway.sendText(text) }
    func close() {
        gateway.embedOnSelect = false
        closingSnapshot = gateway.snapshot
        resizeTask?.cancel(); gateway.closeMirror(); content = nil; dragWidth = nil
        choices = []; onTooltip?(nil); onLayout?()
    }
    func markSeen(_ id: String) { registry.acknowledge(id); onLayout?() }
    func rename(_ session: AgentSession) { renameValue = session.alias ?? ""; renameID = session.id }
    func saveRename() {
        if let renameID { registry.rename(renameID, alias: renameValue); save() }
        renameID = nil
    }
    func move(_ id: String, before other: String?) { registry.move(id, before: other); save() }
    func moveBy(_ id: String, offset: Int) {
        guard let i = registry.sessions.firstIndex(where: { $0.id == id }) else { return }
        let destination = offset < 0 ? i - 1 : i + 2
        guard destination >= 0, destination <= registry.sessions.count else { return }
        move(id, before: destination < registry.sessions.count ? registry.sessions[destination].id : nil)
    }
    /// Leaving always clears the hover; a pinned notch, or one its visibility holds open, stays open through `railExpanded` anyway.
    func setHover(_ inside: Bool) {
        hoverSerial += 1
        guard !draggingRail else { return }
        let serial = hoverSerial
        if inside { expandedRail = true; onLayout?() }
        else if !panelOpen {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.hoverSerial == serial, !self.draggingRail, !self.panelOpen else { return }
                self.expandedRail = false; self.onLayout?()
            }
        }
    }
    func beginRailDrag(_ pointer: RailPoint) {
        let area = screen.visibleFrame
        let expanded = railExpanded
        let height = expanded ? railHeight(available: area.height) : DesignTokens.pillHeight
        let width = railFrameWidth(expanded: expanded)
        let frame = RailGeometry.frame(area: .init(x: area.minX, y: area.minY, width: area.width, height: area.height),
            edge: preferences.edge, position: preferences.railPosition, width: width, height: height)
        railDrag = RailDrag(pointer: pointer, centerY: frame.y + frame.height / 2)
        railDragStart = pointer; railDragStartX = frame.x
        draggingRail = true; hoverSerial += 1; resizeTask?.cancel(); onTooltip?(nil)
    }
    func dragRail(_ pointer: RailPoint) {
        guard let railDrag else { return }
        let location = NSPoint(x: pointer.x, y: pointer.y)
        let target = NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? screen
        let area = target.visibleFrame
        let expanded = railExpanded
        let height = expanded ? railHeight(available: area.height) : DesignTokens.pillHeight
        let placement = railDrag.placement(pointer: pointer,
            screenID: (target.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
            area: .init(x: area.minX, y: area.minY, width: area.width, height: area.height), height: height)
        preferences.screenID = placement.screenID; preferences.edge = placement.edge; preferences.railPosition = placement.position
        if !panelOpen, let start = railDragStart {
            let width = railFrameWidth(expanded: expanded)
            railDragOrigin = RailPoint(x: min(area.maxX - width, max(area.minX, railDragStartX + pointer.x - start.x)),
                                      y: area.minY + area.height * placement.position - height / 2)
        }
        onLayout?()
    }
    func endRailDrag(_ pointer: RailPoint) {
        guard draggingRail else { return }
        dragRail(pointer)
        railDrag = nil; railDragStart = nil; railDragOrigin = nil; draggingRail = false
        persistPreferences()
        let area = screen.visibleFrame
        let expanded = railExpanded
        let height = expanded ? railHeight(available: area.height) : DesignTokens.pillHeight
        let width = railFrameWidth(expanded: expanded)
        let frame = RailGeometry.frame(area: .init(x: area.minX, y: area.minY, width: area.width, height: area.height),
            edge: preferences.edge, position: preferences.railPosition, width: width, height: height)
        setHover(pointer.x >= frame.x && pointer.x <= frame.x + frame.width && pointer.y >= frame.y && pointer.y <= frame.y + frame.height)
    }
    func dragPanel() {
        let area = screen.visibleFrame
        dragWidth = preferences.edge == .left ? NSEvent.mouseLocation.x - area.minX : area.maxX - NSEvent.mouseLocation.x
        onLayout?()
    }
    func endPanelDrag() {
        guard let width = dragWidth else { return }
        dragWidth = nil
        if PanelLayout.shouldClose(draggedWidth: width) { close() }
        else { preferences.panelWidth = max(360, width); persistPreferences() }
    }
    func chooseFile(history isHistory: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]; panel.message = messages.text(isHistory ? "choose_history" : "choose_work")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if isHistory { preferences.historyPath = url.path; history.open(url.path) }
        else {
            preferences.workPath = url.path; work.open(url.path)
            if preferences.historyPath == nil {
                let companion = url.deletingLastPathComponent().appendingPathComponent("history.md").path
                if FileManager.default.fileExists(atPath: companion) { preferences.historyPath = companion; history.open(companion) }
            }
        }
        persistPreferences()
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func resume(_ request: ResumeRequest) {
        guard !resumePending else { return }
        switch registry.resumeDecision(request) {
        case .select(let id): choose(id)
        case .choose(let ids): choices = ids
        case .create(let request):
            guard gateway.connected else { noticeKey = "connection_unavailable"; return }
            resumePending = true; createdID = nil; pendingRequest = request; resumeOrigin = content; gateway.resume(request)
            resumeTimeout?.cancel()
            resumeTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, self?.resumePending == true else { return }
                self?.noticeKey = "resume_uncertain"
            }
        }
    }
    func checkResume() {
        guard resumePending else { return }
        noticeKey = "resume_checking"; gateway.refresh(); resolvePendingResume()
    }
    private func resolvePendingResume() {
        guard resumePending, let pendingRequest else { return }
        switch registry.resumeConfirmation(pendingRequest, createdTerminalID: createdID) {
        case .waiting: break
        case .confirmed(let id): finishResume(id, activate: content == resumeOrigin)
        case .choose(let ids): choices = ids; noticeKey = "choose_session"
        }
    }
    func finishResume(_ id: String, activate: Bool = true) {
        resumeTimeout?.cancel(); resumePending = false; createdID = nil; pendingRequest = nil; resumeOrigin = nil
        if activate {
            if content == id { onActivate?() } else { choose(id) }
        } else { noticeKey = "resume_ready" }
    }
    func setLogin(_ enabled: Bool) {
        do {
            guard Bundle.main.bundleURL.pathExtension == "app" else { noticeKey = "login_unavailable"; return }
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            preferences.startAtLogin = enabled; persistPreferences()
        } catch { noticeKey = "login_unavailable" }
    }
    func shutdown(completion: @escaping () -> Void) {
        stopping = true; retry?.cancel(); resizeTask?.cancel(); resumeTimeout?.cancel()
        work.stop(); history.stop(); save(); gateway.shutdown(completion: completion)
    }
    /// Rectangle where the real iTerm2 window sits: the panel minus the header and the resize strip.
    func terminalCard() -> NSRect {
        let area = screen.visibleFrame
        let layout = PanelLayout(screen: .init(x: area.minX, y: area.minY, width: area.width, height: area.height), edge: preferences.edge, preferredWidth: dragWidth ?? preferences.panelWidth, railWidth: railWindowWidth)
        let width = dragWidth.map { min(layout.maximumWidth, max(1, $0)) } ?? layout.content.width
        let full = NSRect(x: preferences.edge == .left ? area.minX : area.maxX - max(1, width), y: area.minY, width: max(1, width), height: area.height)
        let handle: CGFloat = 5
        let header = PanelMetrics.headerHeight
        if preferences.edge == .left {
            return NSRect(x: full.minX, y: full.minY, width: max(80, full.width - handle), height: max(80, full.height - header))
        }
        return NSRect(x: full.minX + handle, y: full.minY, width: max(80, full.width - handle), height: max(80, full.height - header))
    }
    private func coalesceResize() {
        guard !gateway.embedOnSelect, panelOpen, selected != nil, !draggingRail, dragWidth == nil, gateway.canSend,
              let original = gateway.selected, original.singlePane, !original.fullscreen else { return }
        let area = screen.visibleFrame
        let layout = PanelLayout(screen: .init(x: area.minX, y: area.minY, width: area.width, height: area.height), edge: preferences.edge, preferredWidth: preferences.panelWidth, railWidth: railWindowWidth)
        let columns = min(1000, max(2, Int((layout.content.width - PanelMetrics.terminalChromeWidth) / TerminalCanvas.cellWidth)))
        let rows = min(500, max(1, Int((area.height - PanelMetrics.terminalChromeHeight) / TerminalCanvas.cellHeight)))
        guard original.columns != columns || original.rows != rows else { return }
        let resizeKey = original.identity.id + ":" + original.identity.generation + ":" + String(columns) + ":" + String(rows)
        guard lastResize != resizeKey, gateway.statusCode != "resize_ownership_lost" else { return }
        resizeTask?.cancel()
        let identity = original.identity
        resizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, self.gateway.selected?.identity == identity, self.panelOpen else { return }
            self.lastResize = resizeKey
            self.gateway.resize(columns: columns, rows: rows)
        }
    }
    private func accept(_ evidence: AgentEvidence, baseline: Bool) {
        guard let session = registry.apply(evidence) else { return }
        if let kind = alerts.observe(id: session.id, state: session.state, sequence: session.sequence, kind: evidence.kind, baseline: baseline) {
            notify(session, kind: kind)
            reveal(for: kind)
        }
        resolvePendingResume()
        save(); onLayout?()
    }
    private func save() {
        let folder = project.appendingPathComponent(".notchcontrol")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var stored = registry
            stored.invalidateEvidence()
            stored.reconcile(registry.sessions.map { AgentCandidate(terminal: $0.terminal, provider: $0.provider, project: $0.project, name: $0.provider.displayName) })
            for (name, data) in [("preferences.json", try JSONEncoder().encode(preferences)), ("sessions.json", try JSONEncoder().encode(stored))] {
                let path = folder.appendingPathComponent(name)
                try data.write(to: path, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            }
        } catch { noticeKey = "file_unavailable" }
    }
    /// Opens the folded notch until the pointer leaves, or pins it, as the alert's preference asks.
    /// Without the pin on the notch, pinning is not possible and the alert only opens it.
    private func reveal(for kind: AlertKind) {
        switch (kind == .waiting ? preferences.waiting : preferences.completed).notchAction {
        case .nothing: break
        case .pin where preferences.showsPin: if !preferences.alwaysVisible { togglePin() }
        case .open, .pin: if !railExpanded { expandedRail = true; onLayout?() }
        }
    }
    private func notify(_ session: AgentSession, kind: AlertKind) {
        let setting = kind == .waiting ? preferences.waiting : preferences.completed
        if setting.sound { NSSound(named: NSSound.Name(setting.soundName))?.play() }
        guard setting.notification, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let label = session.alias.flatMap { $0.isEmpty ? nil : $0 } ?? URL(fileURLWithPath: session.project).lastPathComponent
        let title = "\(session.provider.displayName) · \(label)"
        let body = messages.text(kind == .waiting ? "waiting" : "completed")
        let identifier = session.id
        let center = UNUserNotificationCenter.current()
        Task { @MainActor [weak self] in
            let status = await center.notificationSettings().authorizationStatus
            var allowed = status == .authorized || status == .provisional
            if status == .notDetermined, self?.notificationRequested == false {
                self?.notificationRequested = true
                allowed = (try? await center.requestAuthorization(options: [.alert, .badge])) ?? false
            }
            guard allowed else { self?.noticeKey = "notification_denied"; return }
            let content = UNMutableNotificationContent(); content.title = title; content.body = body
            content.userInfo = ["session": identifier]
            try? await center.add(UNNotificationRequest(identifier: identifier + ":" + String(session.sequence), content: content, trigger: nil))
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["session"] as? String
        await MainActor.run {
            guard let id, registry.sessions.contains(where: { $0.id == id }) else {
                if content != "report" { choose("report") }
                noticeKey = "session_closed"; onActivate?(); return
            }
            if content == id { onActivate?() } else { choose(id) }
        }
    }
}

/// One row of the notch: a session, a work entry (with its open session), or a divider between work mode groups.
enum RailRow: Identifiable {
    case session(AgentSession)
    case entry(WorkItem, AgentSession?)
    case divider(Int)
    var id: String {
        switch self {
        case .session(let session): session.id
        case .entry(let item, _): item.id
        case .divider(let index): "divider:\(index)"
        }
    }
}

struct SetupDiagnostic: Decodable {
    let version: Int
    let itermInstalled: Bool
    let apiEnabled: Bool?
    let sdkVersion: String?
    let pythonAvailable: Bool
    let providers: [String: Bool]
}
