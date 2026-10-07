import XCTest
@testable import NotchControlCore

final class ContextMissingTests: XCTestCase {
    private func session(_ provider: AgentProvider, _ kind: AgentEventKind?) -> AgentSession {
        var registry = AgentRegistry()
        let candidate = AgentCandidate(terminal: .init(id: "one", generation: "test"), provider: provider, project: "/project", name: provider.displayName)
        registry.reconcile([candidate])
        if let kind {
            registry.apply(AgentEvidence(terminal: candidate.terminal, provider: provider, conversation: nil, sequence: 1, kind: kind, associationProven: true))
        }
        return registry.sessions[0]
    }

    func testOnlyClaudeAndCodexReadTheContextFromTheirStatusBar() {
        XCTAssertEqual(AgentProvider.allCases.filter(\.reportsContext), [.claude, .codex])
    }

    func testAMissingReadingIsReportedOnlyForARecognizedScreenOfAProviderThatCanCarryIt() {
        for provider in AgentProvider.allCases {
            for kind in [AgentEventKind.working, .waiting, .completed, .interrupted] {
                XCTAssertEqual(session(provider, kind).contextIsMissing(nil), provider.reportsContext, "\(provider) \(kind)")
            }
            XCTAssertFalse(session(provider, nil).contextIsMissing(nil), "\(provider): nothing recognized yet")
            XCTAssertFalse(session(provider, .unavailable).contextIsMissing(nil), "\(provider): screen not recognized")
        }
    }

    func testARealReadingIsNeverReportedAsMissing() {
        for provider in [AgentProvider.claude, .codex] {
            XCTAssertFalse(session(provider, .completed).contextIsMissing(0), "\(provider): zero is a reading")
            XCTAssertFalse(session(provider, .working).contextIsMissing(42), "\(provider)")
        }
    }
}
