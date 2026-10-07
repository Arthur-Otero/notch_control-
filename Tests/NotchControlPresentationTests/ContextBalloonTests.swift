import AppKit
import NotchControlCore
import SwiftUI
import XCTest
@testable import NotchControl
@testable import NotchControlUI

final class ContextBalloonTests: XCTestCase {
    private func session(_ provider: AgentProvider, _ kind: AgentEventKind?) -> AgentSession {
        var registry = AgentRegistry()
        let candidate = AgentCandidate(terminal: .init(id: "one", generation: "test"), provider: provider, project: "/project", name: provider.displayName)
        registry.reconcile([candidate])
        if let kind {
            registry.apply(AgentEvidence(terminal: candidate.terminal, provider: provider, conversation: nil, sequence: 1, kind: kind, associationProven: true))
        }
        return registry.sessions[0]
    }

    @MainActor
    func testTheBalloonSaysWhyThereIsNoContextBarAndStillFits() {
        for language in [InterfaceLanguage.portuguese, .english] {
            let messages = Messages(language: language)
            XCTAssertGreaterThan(messages.text("context_missing").count, 20, "\(language): the key exists")
            for provider in [AgentProvider.claude, .codex] {
                let hint = messages.contextMissing(provider)
                XCTAssertTrue(hint.contains(provider.displayName), "\(language) \(provider): \(hint)")
                XCTAssertFalse(hint.contains("%@"), "\(language) \(provider)")
                func height(_ session: AgentSession, context: Double?) -> CGFloat {
                    let host = NSHostingView(rootView: SessionDetails(session: session, context: context, windows: [], messages: messages))
                    XCTAssertEqual(host.fittingSize.width, DesignTokens.tooltipWidth, accuracy: 1)
                    return host.fittingSize.height
                }
                let explained = height(session(provider, .completed), context: nil)
                XCTAssertGreaterThan(explained, height(session(provider, nil), context: nil), "\(language) \(provider): the hint takes a line")
                XCTAssertLessThan(explained, 320, "\(language) \(provider)")
                XCTAssertGreaterThan(height(session(provider, .completed), context: 40), 100, "\(language) \(provider): the bar replaces the hint")
            }
        }
    }
}
