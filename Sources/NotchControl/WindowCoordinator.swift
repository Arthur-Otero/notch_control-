import AppKit
import Combine
import NotchControlCore
import NotchControlUI
import QuartzCore
import SwiftUI

@MainActor
final class QuietHostingView<Content: View>: NSHostingView<Content> {
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }
}

@MainActor
final class PersistentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) {}
    override func sendEvent(_ event: NSEvent) {
        // A nonactivating panel does not take the click otherwise, so the session button never fires.
        if event.type == .leftMouseDown, !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }
}

@MainActor
final class WindowCoordinator {
    let store: AppStore
    private let panel: PersistentPanel
    private let rail: PersistentPanel
    private let sash: PersistentPanel
    private var lastCard: NSRect?
    private var wasOpen = false
    private var wasExpanded = false
    private var transitionSerial = 0
    private var lastRailFrame: NSRect?
    private var lastPanelFrame: NSRect?
    private var settings: NSWindow?
    private var tooltip: NSPanel?
    private var tooltipID: String?
    private var tooltipAnchor = NSPoint.zero
    private var tooltipUpdates: AnyCancellable?
    init(store: AppStore) {
        self.store = store
        panel = Self.makePanel(level: .floating)
        rail = Self.makePanel(level: NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1))
        panel.contentView = QuietHostingView(rootView: PanelSurface(store: store))
        rail.contentView = QuietHostingView(rootView: NotchSurface(store: store))
        sash = Self.makePanel(level: .floating)
        sash.contentView = QuietHostingView(rootView: ResizeSash(store: store))
        store.onLayout = { [weak self] in self?.layout() }
        store.onActivate = { [weak self] in self?.activate() }
        store.onSettings = { [weak self] in self?.showSettings() }
        store.onTooltip = { [weak self] id in self?.showTooltip(id) }
        tooltipUpdates = store.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshTooltip()
        }
    }
    /// No system shadow on any window: macOS 26 outlines a shadowed window with a light gray rim, and the notch, panel
    /// and balloon are meant to be pure black.
    private static func makePanel(level: NSWindow.Level) -> PersistentPanel {
        let window = PersistentPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isFloatingPanel = true; window.level = level; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.isReleasedWhenClosed = false; window.title = "NotchControl"
        return window
    }
    func layout() {
        let area = store.screen.visibleFrame
        let open = store.panelOpen
        let expanded = store.railExpanded
        let width = expanded ? DesignTokens.railWidth : DesignTokens.pillWidth
        let height = expanded ? store.railHeight(available: area.height) : min(area.height, DesignTokens.pillHeight)
        let screen = ScreenArea(x: area.minX, y: area.minY, width: area.width, height: area.height)
        let layout = PanelLayout(screen: screen, edge: store.preferences.edge, preferredWidth: store.preferences.panelWidth, railWidth: DesignTokens.railWidth)
        let contentWidth = open ? store.dragWidth.map { min(layout.maximumWidth, max(1, $0)) } ?? layout.content.width : 0
        let frame = RailGeometry.frame(area: screen, edge: store.preferences.edge, position: store.preferences.railPosition, width: width, height: height)
        let direction: CGFloat = store.preferences.edge == .left ? 1 : -1
        let railFrame = NSRect(x: store.railDragOrigin?.x ?? frame.x + direction * contentWidth,
                               y: store.railDragOrigin?.y ?? frame.y, width: frame.width, height: frame.height)
        let fullPanel = NSRect(x: store.preferences.edge == .left ? area.minX : area.maxX - max(1, contentWidth),
                               y: area.minY, width: max(1, contentWidth), height: area.height)
        let hosting = open && store.presentedSession != nil && store.gateway.embedOnSelect && !store.gateway.dockFailed
        let header = PanelMetrics.headerHeight
        let panelFrame = hosting
            ? NSRect(x: fullPanel.minX, y: fullPanel.maxY - header, width: fullPanel.width, height: header)
            : fullPanel
        let handle: CGFloat = 5
        let sashFrame = NSRect(x: store.preferences.edge == .left ? fullPanel.maxX - handle : fullPanel.minX,
                               y: fullPanel.minY, width: handle, height: max(1, fullPanel.height - header))
        let changed = open != wasOpen || expanded != wasExpanded
        let resized = expanded && wasExpanded && lastRailFrame?.height != railFrame.height
        guard changed || lastRailFrame != railFrame || lastPanelFrame != panelFrame else { return }
        lastRailFrame = railFrame; lastPanelFrame = panelFrame
        let animate = (changed || resized) && !store.draggingRail && store.dragWidth == nil && rail.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        transitionSerial += 1
        let serial = transitionSerial
        if open && !wasOpen && !hosting {
            panel.setFrame(NSRect(x: store.preferences.edge == .left ? area.minX : area.maxX - 1, y: area.minY, width: 1, height: area.height), display: false)
        }
        if open { panel.orderFrontRegardless() }
        let closing = wasOpen && !open
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? (open != wasOpen ? 0.32 : resized ? NotchMotion.duration : 0.2) : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            if animate {
                rail.animator().setFrame(railFrame, display: true)
                if open || closing { panel.animator().setFrame(panelFrame, display: true) }
            } else {
                rail.setFrame(railFrame, display: true)
                if open || closing { panel.setFrame(panelFrame, display: true) }
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transitionSerial == serial, !self.store.panelOpen else { return }
                self.panel.orderOut(nil)
            }
        }
        wasOpen = open; wasExpanded = expanded
        if !open && !closing { panel.orderOut(nil) }
        if hosting {
            sash.setFrame(sashFrame, display: true)
            sash.orderFrontRegardless()
            let card = store.terminalCard()
            if store.gateway.docked, card != lastCard {
                lastCard = card
                store.gateway.place(card)
            }
        } else {
            lastCard = nil
            sash.orderOut(nil)
        }
        rail.orderFrontRegardless()
    }
    func activate() { NSApp.activate(ignoringOtherApps: true); (store.panelOpen ? panel : rail).makeKeyAndOrderFront(nil) }
    func showSettings() {
        showTooltip(nil)
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 500, height: 450)
            window.contentView = NSHostingView(rootView: SettingsView(store: store)); window.center()
            settings = window
        }
        settings?.title = store.messages.text("settings")
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    private func showTooltip(_ id: String?) {
        tooltipID = id
        tooltipAnchor = NSEvent.mouseLocation
        refreshTooltip()
    }
    private func refreshTooltip() {
        let row = tooltipID.flatMap { id in store.railRows.first { $0.id == id } }
        let session: AgentSession?, item: WorkItem?
        switch row {
        case .session(let value): (session, item) = (value, nil)
        case .entry(let value, let open): (session, item) = (open, value)
        case .divider, nil: (session, item) = (nil, nil)
        }
        guard !store.draggingRail, session != nil || item != nil else {
            tooltip?.orderOut(nil)
            return
        }
        let area = store.screen.visibleFrame
        let panel = tooltip ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.hasShadow = false
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        let windows = session.flatMap { session in
            store.gateway.accountUsage[session.terminal.id].flatMap { $0.terminal == session.terminal ? $0.windows : nil }
        } ?? []
        let left = store.preferences.edge == .left
        let host = NSHostingView(rootView: SessionDetails(session: session, item: item, windows: windows, messages: store.messages, tailOnLeft: left))
        let height = min(host.fittingSize.height, area.height)
        let width = DesignTokens.tooltipWidth
        let y = min(max(area.minY, tooltipAnchor.y - height / 2), area.maxY - height)
        host.rootView.tailY = height - (tooltipAnchor.y - y)
        panel.contentView = host
        let x = left ? rail.frame.maxX + 4 : rail.frame.minX - width - 4
        panel.setFrame(NSRect(x: min(max(area.minX, x), area.maxX - width), y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless(); tooltip = panel
    }
}

private struct NotchSurface: View {
    @ObservedObject var store: AppStore
    var body: some View {
        Group {
            if store.railExpanded {
                RailView(store: store)
            } else {
                FoldedRailView(store: store)
            }
        }.preferredColorScheme(.dark)
    }
}

private struct ResizeSash: View {
    @ObservedObject var store: AppStore
    var body: some View {
        Rectangle().fill(Color.clear).contentShape(Rectangle())
            .overlay {
                RailDragHandle(label: store.messages.text("resize_label"), onBegin: { _ in },
                    onMove: { _ in store.dragPanel() }, onEnd: { _ in store.endPanelDrag() }, horizontalResize: true,
                    onAdjust: { delta in store.preferences.panelWidth += Double(delta) * 40; store.persistPreferences() })
                    .focusEffectDisabled()
            }.help(store.messages.text("resize_label")).accessibilityLabel(store.messages.text("resize_label"))
    }
}

private struct PanelSurface: View {
    @ObservedObject var store: AppStore
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if store.preferences.edge == .right { resizeHandle }
                PanelContent(store: store).frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.preferences.edge == .left { resizeHandle }
            }
            .frame(width: contentWidth, height: geometry.size.height)
            .frame(width: geometry.size.width, alignment: store.preferences.edge == .left ? .leading : .trailing)
            .background(DesignTokens.notch)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: store.preferences.edge == .right ? DesignTokens.notchRadius : 0,
                bottomLeadingRadius: store.preferences.edge == .right ? DesignTokens.notchRadius : 0,
                bottomTrailingRadius: store.preferences.edge == .left ? DesignTokens.notchRadius : 0,
                topTrailingRadius: store.preferences.edge == .left ? DesignTokens.notchRadius : 0))
            .allowsHitTesting(store.panelOpen)
        }.preferredColorScheme(.dark)
    }
    private var contentWidth: CGFloat {
        let area = store.screen.visibleFrame
        let layout = PanelLayout(screen: .init(x: area.minX, y: area.minY, width: area.width, height: area.height), edge: store.preferences.edge,
                                 preferredWidth: store.preferences.panelWidth, railWidth: DesignTokens.railWidth)
        return store.dragWidth.map { min(layout.maximumWidth, max(1, $0)) } ?? layout.content.width
    }
    private var resizeHandle: some View {
        Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: 5)
            .overlay {
                RailDragHandle(label: store.messages.text("resize_label"), onBegin: { _ in },
                    onMove: { _ in store.dragPanel() }, onEnd: { _ in store.endPanelDrag() }, horizontalResize: true,
                    onAdjust: { delta in store.preferences.panelWidth += Double(delta) * 40; store.persistPreferences() })
                    .focusEffectDisabled()
            }.help(store.messages.text("resize_label"))
            .accessibilityLabel(store.messages.text("resize_label"))
    }
}
