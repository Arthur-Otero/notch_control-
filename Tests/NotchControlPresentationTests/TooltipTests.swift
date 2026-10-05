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
        let readings: [(String, [AccountUsageWindow])] = [
            ("empty", []),
            ("zero", [.init(id: "five_hour", usedPercent: 0)]),
            ("limits", [.init(id: "five_hour", usedPercent: 33), .init(id: "seven_day", usedPercent: 92)]),
            ("cursor", [.init(id: "cursor", usedPercent: 31.8), .init(id: "other_models", usedPercent: 75.6, resetHint: "15m")])
        ]
        for language in [InterfaceLanguage.portuguese, .english] {
            for left in [true, false] {
                for (name, windows) in readings {
                    let content = SessionDetails(session: session, windows: windows, messages: Messages(language: language), tailOnLeft: left)
                    let host = NSHostingView(rootView: content)
                    XCTAssertEqual(host.fittingSize.width, DesignTokens.tooltipWidth, accuracy: 1)
                    XCTAssertGreaterThan(host.fittingSize.height, 120)
                    XCTAssertLessThan(host.fittingSize.height, 300)
                    let renderer = ImageRenderer(content: content.background(Color(red: 0.12, green: 0.14, blue: 0.18)))
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.cgImage)
                    XCTAssertEqual(image.width, 600)
                    if let folder = ProcessInfo.processInfo.environment["NC_RENDER_DIR"] {
                        let bitmap = NSBitmapImageRep(cgImage: image)
                        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("tooltip-\(language.rawValue)-\(left ? "left" : "right")-\(name).png"))
                    }
                }
            }
        }
    }
}
