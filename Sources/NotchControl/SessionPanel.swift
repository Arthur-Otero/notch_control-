import AppKit
import NotchControlCore
import NotchControlUI
import SwiftUI

struct PanelContent: View {
    @ObservedObject var store: AppStore
    private var m: Messages { store.messages }
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(store: store)
            Divider().overlay(DesignTokens.border.opacity(0.6))
            if store.presentedContent == "report" {
                ReportPanel(store: store)
            } else if let session = store.presentedSession {
                SessionPanelBody(store: store).id(session.id)
            } else {
                Text(m.text("session_closed")).foregroundStyle(DesignTokens.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.foregroundStyle(DesignTokens.text).background(DesignTokens.notch)
    }
}

private struct PanelHeader: View {
    @ObservedObject var store: AppStore
    private var m: Messages { store.messages }
    var body: some View {
        HStack(spacing: DesignTokens.regular + 2) {
            if store.presentedContent == "report" {
                Image(systemName: "doc.text").font(.system(size: 15)).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.text("report")).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(m.text("file_read_only")).font(.system(size: 11)).foregroundStyle(DesignTokens.muted).lineLimit(1)
                }
                Spacer()
            } else if let session = store.presentedSession {
                SessionBadge(session: session, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text("\(session.provider.displayName) · \(session.projectName)")
                        .font(.system(size: 11)).foregroundStyle(DesignTokens.muted).lineLimit(1)
                }
                Spacer(minLength: DesignTokens.compact)
                    .contentShape(Rectangle())
                    .onTapGesture { if store.gateway.docked { store.gateway.focusEmbedded() } }
                StatePill(state: session.state, messages: m)
            } else {
                Text(m.text("session_closed")).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            HStack(spacing: 2) {
                headerButton("gearshape", key: "settings") { store.onSettings?() }
                headerButton("xmark", key: "close", action: store.close).keyboardShortcut("w", modifiers: .command)
            }
        }.padding(.horizontal, DesignTokens.content).frame(height: PanelMetrics.headerHeight)
    }
    private func headerButton(_ symbol: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(DesignTokens.muted)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).help(m.text(key)).accessibilityLabel(m.text(key))
    }
}

/// Logo do provedor em anel, com a mesma linguagem do notch: trabalhando gira em verde, espera mostra `!`.
struct SessionBadge: View {
    let session: AgentSession
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body: some View {
        ZStack {
            Circle().fill(DesignTokens.notch)
            Circle().strokeBorder(DesignTokens.ringTrack, lineWidth: 3)
            ProviderMark(provider: session.provider).frame(width: size * 0.5, height: size * 0.5)
            if session.state == .working {
                if reducedMotion { Circle().strokeBorder(DesignTokens.activity, lineWidth: 2) }
                else {
                    TimelineView(.periodic(from: .now, by: 0.12)) { timeline in
                        Circle().inset(by: 1.5).trim(from: 0, to: 0.72)
                            .stroke(DesignTokens.activity, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90))
                    }
                }
            }
        }.frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if session.state == .waiting {
                    Text("!").font(.system(size: 10, weight: .heavy)).foregroundStyle(DesignTokens.notch)
                        .frame(width: 13, height: 13).background(DesignTokens.danger, in: Circle()).offset(x: 3, y: -3)
                }
            }.accessibilityHidden(true)
    }
}

private struct StatePill: View {
    let state: AgentState
    let messages: Messages
    var body: some View {
        // Sem evidência o estado é desconhecido e nada é exibido: o cabeçalho não afirma o que não sabe.
        if state != .unknown {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(messages.text(state.rawValue)).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }.padding(.horizontal, 9).padding(.vertical, 5)
                .background(DesignTokens.surface, in: Capsule())
                .foregroundStyle(state == .waiting ? DesignTokens.danger : DesignTokens.text)
                .accessibilityElement(children: .combine)
        }
    }
    private var color: Color {
        switch state {
        case .working: DesignTokens.activity
        case .waiting: DesignTokens.danger
        default: DesignTokens.muted
        }
    }
}

private struct SessionPanelBody: View {
    @ObservedObject var store: AppStore
    private var m: Messages { store.messages }
    private var canType: Bool { store.panelOpen && store.gateway.canSend }
    private var bannerKey: String? {
        if let key = store.noticeKey { return key }
        return ["ready", "connected", "closed", "starting"].contains(store.gateway.statusCode) ? nil : store.gateway.statusCode
    }

    var body: some View {
        VStack(spacing: 0) {
            if let key = bannerKey { banner(key) }
            if store.gateway.embedOnSelect, !store.gateway.dockFailed {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture { store.gateway.focusEmbedded() }
            } else {
                output
            }
        }
    }

    private func banner(_ key: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 12)).padding(.top, 1)
            Text(m.text(key)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if store.noticeKey != nil {
                Button { store.noticeKey = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).accessibilityLabel(m.text("dismiss"))
            }
        }.foregroundStyle(DesignTokens.muted).padding(.horizontal, 12).padding(.vertical, 8)
            .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.controlRadius + 2))
            .padding(.horizontal, PanelMetrics.outputInset).padding(.top, DesignTokens.compact)
    }

    private var output: some View {
        TerminalMirror(snapshot: store.gateway.snapshot ?? store.closingSnapshot, enabled: canType, send: store.sendText,
                       history: store.gateway.history, historyRevision: store.gateway.historyRevision, historyOnly: store.olderHistory,
                       focusOnSelection: true,
                       labels: ["empty": m.text("connecting"), "terminal": m.text("terminal_label"), "paste_title": m.text("paste_title"),
                                "paste_message": m.text("paste_message"), "paste": m.text("paste"), "cancel": m.text("cancel")])
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.regular))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.regular).strokeBorder(DesignTokens.border.opacity(0.5), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if store.gateway.historyHasMore, !store.olderHistory {
                    pill("older_history", symbol: "clock.arrow.circlepath", action: store.showOlderHistory)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if store.olderHistory { pill("jump_end", symbol: "arrow.down.to.line", action: store.jumpToEnd) }
            }
            .padding(.horizontal, PanelMetrics.outputInset).padding(.top, DesignTokens.compact).padding(.bottom, PanelMetrics.outputInset - 2)
    }

    private func pill(_ key: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(m.text(key), systemImage: symbol).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.border.opacity(0.6)))
        }.buttonStyle(.plain).padding(DesignTokens.regular)
    }
}

