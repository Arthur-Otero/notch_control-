import AppKit
import NotchControlCore
import NotchControlUI
import SwiftUI

private struct NotchPreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var notchPreview: Bool {
        get { self[NotchPreviewKey.self] }
        set { self[NotchPreviewKey.self] = newValue }
    }
}

struct RailView: View {
    @ObservedObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.notchPreview) private var preview
    @State private var hoverTask: Task<Void, Never>?
    private var m: Messages { store.messages }
    var body: some View {
        GeometryReader { geometry in
        ZStack(alignment: .top) {
            SideNotchShape(edge: store.preferences.edge, tab: NotchMetrics.tabDepth, tabHeight: NotchMetrics.tabHeight).fill(DesignTokens.notch)
            VStack(spacing: 0) {
            titled {
                VStack(spacing: 0) {
                    Button { store.choose("report") } label: {
                        ZStack {
                            Image(systemName: "doc.text").font(.system(size: DesignTokens.glyphSize))
                            if store.content == "report" { Circle().strokeBorder(DesignTokens.notchInk, lineWidth: 1).padding(-3) }
                        }.frame(width: DesignTokens.iconSize, height: DesignTokens.iconSize)
                    }.buttonStyle(.plain).help(m.text("report")).accessibilityLabel(m.text("report"))
                    Rectangle().fill(DesignTokens.ringTrack).frame(width: DesignTokens.iconSize, height: 1).padding(.top, 12).padding(.bottom, 20)
                }
            } title: { Color.clear.frame(height: 1) }
            if preview { sessionRows.frame(maxHeight: .infinity, alignment: .top).clipped() }
            else {
                ScrollView(.vertical) { sessionRows }
                    .scrollIndicators(needsScrolling ? .visible : .hidden)
                    .scrollDisabled(!needsScrolling)
                    .scrollBounceBehavior(.basedOnSize)
            }
            }.padding(.top, DesignTokens.flare + DesignTokens.topPadding)
             .padding(.bottom, DesignTokens.flare + DesignTokens.bottomPadding)
             .padding(right ? .leading : .trailing, NotchMetrics.tabDepth)
        }.foregroundStyle(DesignTokens.notchInk)
         .frame(width: store.railWindowWidth, height: geometry.size.height, alignment: .top)
         .frame(width: geometry.size.width, alignment: right ? .trailing : .leading)
         .clipped()
         .overlay(alignment: right ? .topTrailing : .topLeading) { if !preview { bodyDrag().frame(width: DesignTokens.railWidth, height: bodyDragTop) } }
         .overlay(alignment: right ? .bottomTrailing : .bottomLeading) { if !preview { bodyDrag().frame(width: DesignTokens.railWidth, height: bodyDragBottom) } }
         .overlay(alignment: .topLeading) { if !preview { bodyDrag().frame(width: bodyDragGutter, height: bodyDragMiddle(geometry.size.height)).padding(.top, bodyDragTop).padding(.leading, right ? innerInset : 0) } }
         .overlay(alignment: .topTrailing) { if !preview && !needsScrolling { bodyDrag().frame(width: bodyDragGutter, height: bodyDragMiddle(geometry.size.height)).padding(.top, bodyDragTop).padding(.trailing, right ? 0 : innerInset) } }
         .overlay(alignment: right ? .leading : .trailing) { titlesTab }
        }
            .onHover(perform: store.setHover)
            .onChange(of: store.content) { _, _ in hoverTask?.cancel(); store.onTooltip?(nil) }
            .onChange(of: store.railRows.map(\.id)) { _, _ in hoverTask?.cancel(); store.onTooltip?(nil) }
            .onDisappear { hoverTask?.cancel(); store.onTooltip?(nil) }
            .sheet(isPresented: Binding(get: { store.renameID != nil }, set: { if !$0 { store.renameID = nil } })) {
                VStack(alignment: .leading, spacing: DesignTokens.content) {
                    Text(m.text("rename")).font(.headline)
                    TextField(m.text("alias"), text: $store.renameValue).textFieldStyle(.roundedBorder)
                    HStack { Button(m.text("cancel")) { store.renameID = nil }; Spacer(); Button(m.text("save"), action: store.saveRename).keyboardShortcut(.defaultAction) }
                }.padding(DesignTokens.content).frame(width: 300).background(DesignTokens.surface)
            }
    }
    private var right: Bool { store.preferences.edge == .right }
    /// Room on the inner side of the bubble column: the tab and, when open, the titles.
    private var innerInset: CGFloat { store.railWindowWidth - DesignTokens.railWidth }
    /// Bubble column plus, when the titles are open, the title column on the inner side.
    private func titled<Bubble: View, Title: View>(@ViewBuilder _ bubble: () -> Bubble, @ViewBuilder title: () -> Title) -> some View {
        HStack(spacing: 0) {
            if right && store.titlesOpen { title().frame(width: NotchMetrics.titlesWidth, alignment: .leading) }
            bubble().frame(width: DesignTokens.railWidth)
            if !right && store.titlesOpen { title().frame(width: NotchMetrics.titlesWidth, alignment: .leading) }
        }
    }
    /// Same action and balloon as the bubble beside it; the bubble already carries the accessible name.
    private func titleLabel(id: String, primary: String, secondary: String?, dimmed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(primary).font(.system(size: 13, weight: .medium)).lineLimit(secondary == nil ? 2 : 1)
                    .foregroundStyle(dimmed ? DesignTokens.muted : DesignTokens.notchInk)
                if let secondary { Text(secondary).font(.system(size: 11)).lineLimit(1).foregroundStyle(DesignTokens.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
             .padding(right ? .leading : .trailing, 16).padding(right ? .trailing : .leading, 6)
             .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { inside in tooltip(inside ? id : nil) }.accessibilityHidden(true)
    }
    /// Points where the titles go: inward to open them, back to the edge to close them.
    private var titlesTab: some View {
        Button(action: store.toggleTitles) {
            Image(systemName: right == !store.titlesOpen ? "chevron.left" : "chevron.right").font(.system(size: 11, weight: .bold))
                .frame(width: NotchMetrics.tabDepth + 10, height: NotchMetrics.tabHeight).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(DesignTokens.notchInk)
            .help(m.text(store.titlesOpen ? "hide_titles" : "show_titles")).accessibilityLabel(m.text(store.titlesOpen ? "hide_titles" : "show_titles"))
    }
    private var needsScrolling: Bool {
        let counts = store.railCounts
        return NotchMetrics.needsScrolling(sessions: counts.cells, dividers: counts.dividers, available: store.screen.visibleFrame.height)
    }
    private var sessionRows: some View {
        let rows = store.railRows
        return VStack(spacing: DesignTokens.cellSpacing) {
            ForEach(rows) { row in
                railRow(row)
                    .transition(reducedMotion ? .identity : NotchMotion.sessionTransition)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, rows.isEmpty ? 0 : 4)
            .animation(reducedMotion || store.draggingRail ? nil : NotchMotion.animation, value: rows.map(\.id))
    }
    @ViewBuilder private func railRow(_ row: RailRow) -> some View {
        switch row {
        case .session(let session):
            titled { sessionRow(session) } title: {
                titleLabel(id: session.id, primary: session.title, secondary: session.projectName, dimmed: session.state == .unknown) { store.choose(session.id) }
            }
        case .entry(let item, let session):
            titled { entryRow(item, session: session) } title: {
                titleLabel(id: item.id, primary: item.entry.title, secondary: item.others.isEmpty ? nil : m.sharedSession(item.others.count),
                           dimmed: session == nil) { store.choose(item) }
            }
        case .divider:
            titled { Rectangle().fill(DesignTokens.ringTrack).frame(width: DesignTokens.iconSize, height: 1).accessibilityHidden(true) } title: { Color.clear.frame(height: 1) }
        }
    }
    /// Entries follow the work file order, so they offer details but no rename or move.
    @ViewBuilder private func entryRow(_ item: WorkItem, session: AgentSession?) -> some View {
        let cell = Group {
            if let session {
                SessionButton(session: session, selected: store.content == session.id, reducedMotion: reducedMotion, messages: m,
                    label: m.title(of: item), context: store.contextPercent(session),
                    onFocus: { focused in tooltip(focused ? item.id : nil) }) { store.choose(item) }
            } else {
                WorkButton(item: item, messages: m, onFocus: { focused in tooltip(focused ? item.id : nil) }) { store.choose(item) }
            }
        }.onHover { inside in tooltip(inside ? item.id : nil) }
        if preview { cell }
        else { cell.contextMenu { Button(m.text("details")) { store.onTooltip?(item.id) } } }
    }
    @ViewBuilder private func sessionRow(_ session: AgentSession) -> some View {
        let cell = SessionButton(session: session, selected: store.content == session.id, reducedMotion: reducedMotion, messages: m,
            context: store.contextPercent(session), onFocus: { focused in tooltip(focused ? session.id : nil) }) { store.choose(session.id) }
            .onHover { inside in tooltip(inside ? session.id : nil) }
        if preview { cell }
        else {
            cell.draggable(session.id)
                .dropDestination(for: String.self) { items, _ in
                    guard let id = items.first else { return false }
                    store.move(id, before: session.id); return true
                }
                .contextMenu {
                    Button(m.text("details")) { store.onTooltip?(session.id) }
                    Button(m.text("rename")) { store.rename(session) }
                    Button(m.text("move_before")) { store.moveBy(session.id, offset: -1) }
                    Button(m.text("move_after")) { store.moveBy(session.id, offset: 1) }
                }
        }
    }
    private var bodyDragTop: CGFloat { DesignTokens.flare + DesignTokens.topPadding }
    private var bodyDragBottom: CGFloat { DesignTokens.flare + DesignTokens.bottomPadding }
    private var bodyDragGutter: CGFloat { (DesignTokens.railWidth - DesignTokens.iconSize) / 2 }
    private func bodyDragMiddle(_ height: CGFloat) -> CGFloat { max(0, height - bodyDragTop - bodyDragBottom) }
    private func bodyDrag() -> some View {
        RailDragHandle(label: m.text("position"), onBegin: store.beginRailDrag, onMove: store.dragRail,
            onEnd: store.endRailDrag, contextTitle: m.text("settings"), onContext: { store.onSettings?() },
            exposesAccessibility: false, hint: m.text("drag_notch"))
            .focusEffectDisabled()
    }
    private func tooltip(_ id: String?) {
        hoverTask?.cancel()
        guard let id else { store.onTooltip?(nil); return }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            store.onTooltip?(id)
        }
    }

}

struct FoldedRailView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        SideNotchShape(edge: store.preferences.edge, folded: true).fill(DesignTokens.notch)
            .overlay {
                RailDragHandle(label: store.messages.text("open_notch"), onBegin: store.beginRailDrag,
                    onMove: store.dragRail, onEnd: store.endRailDrag, onClick: { store.choose("report") },
                    contextTitle: store.messages.text("settings"), onContext: { store.onSettings?() },
                    hint: store.messages.text("drag_notch"))
                    .focusEffectDisabled()
            }.onHover(perform: store.setHover)
    }
}

private struct SessionButton: View {
    let session: AgentSession
    let selected: Bool
    let reducedMotion: Bool
    let messages: Messages
    /// Work entry title read in place of the terminal title.
    var label: String? = nil
    var context: Double? = nil
    let onFocus: (Bool) -> Void
    let action: () -> Void
    @FocusState private var focused: Bool
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(hovered ? DesignTokens.background : DesignTokens.notch)
                Circle().strokeBorder(DesignTokens.ringTrack, lineWidth: DesignTokens.trackStroke)
                ProviderMark(provider: session.provider).frame(width: DesignTokens.glyphSize, height: DesignTokens.glyphSize)
                    .opacity(session.state == .unknown ? 0.55 : 1)
                if session.state == .working || session.unseenResult {
                    if session.unseenResult || reducedMotion {
                        Circle().strokeBorder(DesignTokens.activity, lineWidth: DesignTokens.activityStroke).padding(1.5)
                    } else {
                        TimelineView(.periodic(from: .now, by: 0.12)) { timeline in
                            Circle().inset(by: DesignTokens.trackStroke / 2).trim(from: 0, to: 0.72)
                                .stroke(DesignTokens.activity, style: StrokeStyle(lineWidth: DesignTokens.activityStroke, lineCap: .round))
                                .rotationEffect(.degrees(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90))
                        }
                    }
                }
                if selected { Circle().stroke(DesignTokens.notchInk, lineWidth: 1).padding(-3) }
                if focused { Circle().stroke(DesignTokens.focus, style: StrokeStyle(lineWidth: 2, dash: [2, 2])).padding(-3) }
            }.frame(width: DesignTokens.iconSize, height: DesignTokens.iconSize)
             .overlay(alignment: .topTrailing) {
                if session.state == .waiting {
                    Text("!").font(.system(size: 13, weight: .heavy)).foregroundStyle(DesignTokens.notch)
                        .frame(width: 16, height: 16).background(DesignTokens.danger, in: Circle()).offset(x: 3, y: -3)
                }
             }
             // Sits in the gap below the circle, so the notch keeps its height.
             .overlay(alignment: .bottom) {
                if let context {
                    LevelBar(usedPercent: context, level: .context(context), track: DesignTokens.contextTrack)
                        .frame(width: DesignTokens.iconSize, height: 3).offset(y: 8)
                }
             }
        }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }.onChange(of: focused) { _, value in onFocus(value) }.accessibilityLabel(accessibilityText)
    }
    private var accessibilityText: String {
        let text = "\(session.provider.displayName), \(label ?? session.title), \(messages.text(session.state.rawValue))"
        return context.map { text + ", \(messages.text("context")) \(Int($0.rounded()))%" } ?? text
    }
}

/// Used share filled green, yellow or red by its level; any reading above zero shows at least a dot.
struct LevelBar: View {
    let usedPercent: Double
    let level: UsageLevel
    var track = DesignTokens.ringTrack
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if usedPercent > 0 {
                    Capsule().fill(color).frame(width: max(geometry.size.height, geometry.size.width * min(100, usedPercent) / 100))
                }
            }
        }.accessibilityHidden(true)
    }
    private var color: Color {
        switch level {
        case .low: DesignTokens.activity
        case .medium: DesignTokens.warning
        case .high: DesignTokens.danger
        }
    }
}

/// Work entry without an open terminal: the newest session's agent in the track color, or a document when it lists none.
private struct WorkButton: View {
    let item: WorkItem
    let messages: Messages
    let onFocus: (Bool) -> Void
    let action: () -> Void
    @FocusState private var focused: Bool
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(hovered ? DesignTokens.background : DesignTokens.notch)
                Circle().strokeBorder(DesignTokens.ringTrack, lineWidth: DesignTokens.trackStroke)
                WorkMarkIcon(mark: item.mark, tint: DesignTokens.ringTrack).frame(width: DesignTokens.glyphSize, height: DesignTokens.glyphSize)
                if focused { Circle().stroke(DesignTokens.focus, style: StrokeStyle(lineWidth: 2, dash: [2, 2])).padding(-3) }
            }.frame(width: DesignTokens.iconSize, height: DesignTokens.iconSize)
        }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }.onChange(of: focused) { _, value in onFocus(value) }
            .accessibilityLabel(accessibilityText)
    }
    private var accessibilityText: String {
        if case .closed(let request) = item.mark { return "\(request.provider.displayName), \(messages.title(of: item)), \(messages.text("terminal_closed"))" }
        return "\(messages.title(of: item)), \(messages.text("no_session"))"
    }
}

/// Agent logo of a closed entry, or a document for an entry without sessions.
struct WorkMarkIcon: View {
    let mark: WorkMark
    var tint: Color? = nil
    var body: some View {
        switch mark {
        case .open: EmptyView()
        case .closed(let request): ProviderMark(provider: request.provider, tint: tint)
        case .note:
            Image(systemName: "doc.text").resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(tint ?? DesignTokens.notchInk).accessibilityHidden(true)
        }
    }
}

struct ProviderMark: View {
    let provider: AgentProvider
    /// Paints the logo as a silhouette in this color.
    var tint: Color? = nil
    private var image: NSImage? {
        switch provider {
        case .claude: ProviderImages.claude
        case .codex: ProviderImages.openai
        case .cursor: ProviderImages.cursor
        }
    }
    var body: some View {
        if let image, let tint {
            Image(nsImage: image).renderingMode(.template).resizable().aspectRatio(contentMode: .fit).foregroundStyle(tint).accessibilityHidden(true)
        } else if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).accessibilityHidden(true) }
        else {
            Text(String(provider.displayName.prefix(1))).font(.system(size: DesignTokens.glyphSize, weight: .bold))
                .foregroundStyle(tint ?? DesignTokens.notchInk).accessibilityHidden(true)
        }
    }
}

@MainActor
private enum ProviderImages {
    static let claude = Bundle.module.url(forResource: "claude", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
    static let openai = Bundle.module.url(forResource: "openai", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
    static let cursor = Bundle.module.url(forResource: "cursor", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
}

