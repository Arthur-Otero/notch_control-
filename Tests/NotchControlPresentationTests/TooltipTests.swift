import AppKit
import NotchControlCore
import NotchControlUI
import SwiftUI
import XCTest
@testable import NotchControl

final class TooltipTests: XCTestCase {
    @MainActor
    func testTooltipFitsBothEdgesAndAllUsageStates() throws {
        let identity = TerminalIdentity(id: "fixture", generation: "one")
        var registry = AgentRegistry()
        registry.reconcile([AgentCandidate(terminal: identity, provider: .codex,
            project: "/Users/example/Projects/a-long-project-name/notch_control", name: "Implementação do painel (codex)")])
        registry.apply(AgentEvidence(terminal: identity, provider: .codex, conversation: nil, sequence: 1,
            kind: .working, associationProven: true))
        let session = try XCTUnwrap(registry.sessions.first)
        let limits: [AccountUsageWindow] = [.init(id: "five_hour", usedPercent: 33, resetHint: "20/10 18:00"),
                                          .init(id: "seven_day", usedPercent: 92, resetHint: "26/10 09:30")]
        let readings: [(String, [AccountUsageWindow], AccountUsageRefresh?)] = [
            ("empty", [], nil),
            ("zero", [.init(id: "five_hour", usedPercent: 0)], nil),
            ("limits", [.init(id: "five_hour", usedPercent: 33), .init(id: "seven_day", usedPercent: 92)], nil),
            ("codex-reset", limits, .init(updatedAt: Date.now.timeIntervalSince1970)),
            ("loading", [], .init(loading: true)),
            ("updating", limits, .init(loading: true, updatedAt: Date.now.timeIntervalSince1970 - 130)),
            ("stale", limits, .init(updatedAt: Date.now.timeIntervalSince1970 - 240)),
            ("error", limits, .init(updatedAt: Date.now.timeIntervalSince1970 - 240, errorCode: "codex_usage_unavailable")),
            ("rate-limited", [], .init(errorCode: "codex_usage_rate_limited")),
            ("cursor", [.init(id: "cursor", usedPercent: 31.8), .init(id: "other_models", usedPercent: 75.6, resetHint: "15m")], nil)
        ]
        for language in [InterfaceLanguage.portuguese, .english] {
            for left in [true, false] {
                var fixedHeight: CGFloat?
                for (name, windows, refresh) in readings {
                    let content = SessionDetails(session: session, windows: windows, refresh: refresh, messages: Messages(language: language), tailOnLeft: left)
                    let host = NSHostingView(rootView: content)
                    XCTAssertEqual(host.fittingSize.width, DesignTokens.tooltipWidth, accuracy: 1)
                    XCTAssertGreaterThan(host.fittingSize.height, 120)
                    XCTAssertLessThan(host.fittingSize.height, 380)
                    if let fixedHeight { XCTAssertEqual(host.fittingSize.height, fixedHeight, accuracy: 1, name) }
                    else { fixedHeight = host.fittingSize.height }
                    let renderer = ImageRenderer(content: content.background(Color(red: 0.12, green: 0.14, blue: 0.18)))
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.cgImage)
                    XCTAssertEqual(image.width, 600)
                    if let folder = ProcessInfo.processInfo.environment["NC_RENDER_DIR"] {
                        let bitmap: NSBitmapImageRep
                        if refresh?.loading == true {
                            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                                  styleMask: [.borderless], backing: .buffered, defer: false)
                            window.isReleasedWhenClosed = false
                            window.appearance = NSAppearance(named: .darkAqua)
                            window.contentView = host
                            host.frame = NSRect(origin: .zero, size: host.fittingSize)
                            host.layoutSubtreeIfNeeded()
                            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
                            bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                            host.cacheDisplay(in: host.bounds, to: bitmap)
                        } else {
                            bitmap = NSBitmapImageRep(cgImage: image)
                        }
                        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("tooltip-\(language.rawValue)-\(left ? "left" : "right")-\(name).png"))
                    }
                }
            }
        }
    }

    func testReadingAgeIsLocalizedAndNeverUsesAnUnboundedSecondsCounter() {
        let now = Date(timeIntervalSince1970: 100000)
        let portuguese = Messages(language: .portuguese)
        let english = Messages(language: .english)
        XCTAssertEqual(portuguese.usageAge(99990, now: now), "Última leitura agora")
        XCTAssertEqual(portuguese.usageAge(99880, now: now), "Última leitura há 2 min")
        XCTAssertEqual(english.usageAge(99880, now: now), "Last checked 2 min ago")
        XCTAssertEqual(english.usageAge(92800, now: now), "Last checked 2 h ago")
    }
}
