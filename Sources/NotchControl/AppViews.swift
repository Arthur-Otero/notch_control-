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
            SideNotchShape(edge: store.preferences.edge).fill(DesignTokens.notch)
            VStack(spacing: 0) {
            Button { store.choose("report") } label: {
                ZStack {
                    Image(systemName: "doc.text").font(.system(size: DesignTokens.glyphSize))
                    if store.content == "report" { Circle().strokeBorder(DesignTokens.notchInk, lineWidth: 1).padding(-3) }
                }.frame(width: DesignTokens.iconSize, height: DesignTokens.iconSize)
            }.buttonStyle(.plain).help(m.text("report")).accessibilityLabel(m.text("report"))
            Rectangle().fill(DesignTokens.ringTrack).frame(width: DesignTokens.iconSize, height: 1).padding(.top, 12).padding(.bottom, 20)
            if preview { sessionRows.frame(maxHeight: .infinity, alignment: .top).clipped() }
            else {
                ScrollView(.vertical) { sessionRows }
                    .scrollIndicators(needsScrolling ? .visible : .hidden)
                    .scrollDisabled(!needsScrolling)
                    .scrollBounceBehavior(.basedOnSize)
            }
            }.padding(.top, DesignTokens.flare + DesignTokens.topPadding)
             .padding(.bottom, DesignTokens.flare + DesignTokens.bottomPadding)
        }.foregroundStyle(DesignTokens.notchInk)
         .frame(width: DesignTokens.railWidth, height: geometry.size.height, alignment: .top)
         .frame(width: geometry.size.width, alignment: store.preferences.edge == .left ? .leading : .trailing)
         .clipped()
         .overlay(alignment: .top) { if !preview { bodyDrag().frame(height: bodyDragTop) } }
         .overlay(alignment: .bottom) { if !preview { bodyDrag().frame(height: bodyDragBottom) } }
         .overlay(alignment: .topLeading) { if !preview { bodyDrag().frame(width: bodyDragGutter, height: bodyDragMiddle(geometry.size.height)).padding(.top, bodyDragTop) } }
         .overlay(alignment: .topTrailing) { if !preview && !needsScrolling { bodyDrag().frame(width: bodyDragGutter, height: bodyDragMiddle(geometry.size.height)).padding(.top, bodyDragTop) } }
        }.frame(width: DesignTokens.railWidth)
            .onHover(perform: store.setHover)
            .onChange(of: store.content) { _, _ in hoverTask?.cancel(); store.onTooltip?(nil) }
            .onChange(of: store.registry.sessions.map(\.id)) { _, _ in hoverTask?.cancel(); store.onTooltip?(nil) }
            .onDisappear { hoverTask?.cancel(); store.onTooltip?(nil) }
            .sheet(isPresented: Binding(get: { store.renameID != nil }, set: { if !$0 { store.renameID = nil } })) {
                VStack(alignment: .leading, spacing: DesignTokens.content) {
                    Text(m.text("rename")).font(.headline)
                    TextField(m.text("alias"), text: $store.renameValue).textFieldStyle(.roundedBorder)
                    HStack { Button(m.text("cancel")) { store.renameID = nil }; Spacer(); Button(m.text("save"), action: store.saveRename).keyboardShortcut(.defaultAction) }
                }.padding(DesignTokens.content).frame(width: 300).background(DesignTokens.surface)
            }
    }
    private var needsScrolling: Bool {
        NotchMetrics.needsScrolling(sessions: store.registry.sessions.count, available: store.screen.visibleFrame.height)
    }
    private var sessionRows: some View {
        VStack(spacing: DesignTokens.cellSpacing) {
            ForEach(store.registry.sessions) { session in
                sessionRow(session)
                    .transition(reducedMotion ? .identity : NotchMotion.sessionTransition)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, store.registry.sessions.isEmpty ? 0 : 4)
            .animation(reducedMotion || store.draggingRail ? nil : NotchMotion.animation, value: store.registry.sessions.map(\.id))
    }
    @ViewBuilder private func sessionRow(_ session: AgentSession) -> some View {
        let cell = SessionButton(session: session, selected: store.content == session.id, reducedMotion: reducedMotion, messages: m,
            onFocus: { focused in tooltip(focused ? session : nil) }) { store.choose(session.id) }
            .onHover { inside in tooltip(inside ? session : nil) }
        if preview { cell }
        else {
            cell.draggable(session.id)
                .dropDestination(for: String.self) { items, _ in
                    guard let id = items.first else { return false }
                    store.move(id, before: session.id); return true
                }
                .contextMenu {
                    Button(m.text("details")) { store.onTooltip?(session) }
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
    private func tooltip(_ session: AgentSession?) {
        hoverTask?.cancel()
        guard let session else { store.onTooltip?(nil); return }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            store.onTooltip?(session)
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
        }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }.onChange(of: focused) { _, value in onFocus(value) }.accessibilityLabel("\(session.provider.displayName), \(session.title), \(messages.text(session.state.rawValue))")
    }
}

struct ProviderMark: View {
    let provider: AgentProvider
    private var image: NSImage? {
        switch provider {
        case .claude: ProviderImages.claude
        case .codex: ProviderImages.openai
        case .cursor: ProviderImages.cursor
        }
    }
    var body: some View {
        if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).accessibilityHidden(true) }
        else { Text(String(provider.displayName.prefix(1))).font(.system(size: DesignTokens.glyphSize, weight: .bold)).accessibilityHidden(true) }
    }
}

@MainActor
private enum ProviderImages {
    static let claude = Bundle.module.url(forResource: "claude", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
    static let openai = Bundle.module.url(forResource: "openai", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
    static let cursor = Bundle.module.url(forResource: "cursor", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
}

