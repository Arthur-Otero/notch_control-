import NotchControlCore
import NotchControlUI
import SwiftUI

/// Balloon of a session, or of a work entry with or without an open session.
struct SessionDetails: View {
    let session: AgentSession?
    var item: WorkItem? = nil
    let windows: [AccountUsageWindow]
    let messages: Messages
    var tailOnLeft = false
    var tailY: CGFloat?

    private var closed: ResumeRequest? {
        if case .closed(let request) = item?.mark { return request }
        return nil
    }
    private var provider: AgentProvider? { session?.provider ?? closed?.provider }
    private var project: String? { session?.project ?? closed?.directory }
    private var stateColor: Color {
        guard let session else { return DesignTokens.muted }
        return switch session.state {
        case .working: DesignTokens.activity
        case .waiting: DesignTokens.danger
        case .idle: session.unseenResult ? DesignTokens.activity : DesignTokens.muted
        case .unknown: DesignTokens.unknown
        }
    }
    private var status: String {
        guard let session else { return messages.text(closed == nil ? "no_session" : "terminal_closed") }
        let key = session.unseenResult ? "usage_result" : session.state.rawValue
        let reason = session.reason.flatMap { ["approval", "question"].contains($0) ? messages.text($0) : nil }
        return messages.text(key) + (reason.map { " · \($0)" } ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.content) {
            if let item {
                VStack(alignment: .leading, spacing: DesignTokens.compact) {
                    Text(item.entry.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let status = item.entry.status {
                        Text(status).font(.system(size: 12)).lineLimit(4).foregroundStyle(DesignTokens.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            agent
            usage
            VStack(alignment: .leading, spacing: 3) {
                if item == nil, let session {
                    Text(session.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                }
                if let project {
                    Text(project).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(DesignTokens.muted)
                }
                if session != nil, !windows.isEmpty {
                    Text(messages.text("usage_source")).font(.system(size: 10)).foregroundStyle(DesignTokens.muted)
                }
            }
        }.padding(DesignTokens.content)
            .padding(tailOnLeft ? .leading : .trailing, DesignTokens.tooltipTail)
            .frame(width: DesignTokens.tooltipWidth, alignment: .leading)
            .foregroundStyle(DesignTokens.notchInk)
            .background(TooltipBubble(tailOnLeft: tailOnLeft, tailY: tailY).fill(DesignTokens.notch))
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.locale, Locale(identifier: messages.language == .portuguese ? "pt_BR" : "en_US"))
    }
    /// Agent and state; secondary under a work entry's title.
    private var agent: some View {
        let mark: CGFloat = item == nil ? 20 : 16
        return VStack(alignment: .leading, spacing: DesignTokens.compact) {
            HStack(spacing: DesignTokens.compact) {
                if let provider { ProviderMark(provider: provider).frame(width: mark, height: mark) }
                else { WorkMarkIcon(mark: .note).frame(width: mark, height: mark) }
                Text(provider?.displayName ?? messages.text("work_entry"))
                    .font(.system(size: item == nil ? 16 : 13, weight: .semibold)).lineLimit(1)
            }
            HStack(spacing: DesignTokens.compact) {
                Circle().fill(stateColor).frame(width: 6, height: 6)
                Text(status).font(.system(size: 12)).foregroundStyle(stateColor).lineLimit(2)
            }.accessibilityElement(children: .combine)
        }
    }
    @ViewBuilder private var usage: some View {
        if session == nil {
            Text(messages.text(closed == nil ? "note_hint" : "resume_hint")).font(.system(size: 11)).foregroundStyle(DesignTokens.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else if windows.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.compact) {
                Text(messages.text("usage_unavailable")).font(.system(size: 13, weight: .medium))
                Text(messages.text("usage_missing_hint")).font(.system(size: 11)).foregroundStyle(DesignTokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ForEach(windows) { window in
                VStack(alignment: .leading, spacing: DesignTokens.compact) {
                    HStack {
                        Text(messages.text("usage_" + window.id)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(window.usedPercent.formatted(.number.precision(.fractionLength(0...1))
                            .locale(Locale(identifier: messages.language == .portuguese ? "pt_BR" : "en_US"))) + "% " + messages.text("usage_used"))
                            .monospacedDigit().foregroundStyle(DesignTokens.muted)
                    }.font(.system(size: 11))
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DesignTokens.ringTrack)
                            Capsule().fill(window.usedPercent >= 80 ? DesignTokens.danger : DesignTokens.activity)
                                .frame(width: geometry.size.width * min(100, max(0, window.usedPercent)) / 100)
                        }
                    }.frame(height: 5).accessibilityHidden(true)
                    if let reset = window.resetHint {
                        Text(messages.text("usage_resets") + " " + reset)
                            .font(.system(size: 11)).foregroundStyle(DesignTokens.muted)
                    }
                }.accessibilityElement(children: .combine)
            }
        }
    }
}

struct TooltipBubble: Shape {
    var tailOnLeft: Bool
    var tailY: CGFloat?

    func path(in rect: CGRect) -> Path {
        let tail = DesignTokens.tooltipTail
        let body = CGRect(x: tailOnLeft ? tail : 0, y: 0, width: rect.width - tail, height: rect.height)
        let radius = min(DesignTokens.notchRadius, rect.height / 2)
        let y = min(max(radius + tail, tailY ?? rect.midY), rect.height - radius - tail)
        let x = tailOnLeft ? body.minX : body.maxX
        let sign: CGFloat = tailOnLeft ? -1 : 1
        var path = Path(roundedRect: body, cornerRadius: radius)
        path.move(to: CGPoint(x: x - sign, y: y - tail))
        path.addCurve(to: CGPoint(x: x + sign * tail, y: y),
                      control1: CGPoint(x: x, y: y - tail / 2), control2: CGPoint(x: x + sign * tail / 2, y: y - 3))
        path.addCurve(to: CGPoint(x: x - sign, y: y + tail),
                      control1: CGPoint(x: x + sign * tail / 2, y: y + 3), control2: CGPoint(x: x, y: y + tail / 2))
        path.closeSubpath()
        return path
    }
}
