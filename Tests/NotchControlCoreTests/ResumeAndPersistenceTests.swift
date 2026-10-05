import XCTest
@testable import NotchControlCore

final class ResumeAndPersistenceTests: XCTestCase {
    func testResumeSelectsProvenConversationAndOffersChoiceForTwoPhysicalInstances() throws {
        let id = "00000000-0000-0000-0000-000000000001"
        let request = try XCTUnwrap(ResumeRequest(provider: .claude, conversation: id, directory: "/project"))
        var app = AgentRegistry()
        let first = AgentCandidate(terminal: .init(id: "pane1", generation: "101"), provider: .claude, project: "/project", name: "One")
        let second = AgentCandidate(terminal: .init(id: "pane2", generation: "102"), provider: .claude, project: "/project", name: "Two")
        app.reconcile([first, second])
        XCTAssertEqual(app.resumeDecision(request), .create(request))
        app.apply(.init(terminal: first.terminal, provider: .claude, conversation: id, sequence: 1, kind: .working, associationProven: true))
        XCTAssertEqual(app.resumeDecision(request), .select(first.key))
        app.apply(.init(terminal: second.terminal, provider: .claude, conversation: id, sequence: 2, kind: .waiting, associationProven: true))
        XCTAssertEqual(app.resumeDecision(request), .choose([first.key, second.key]))
        app.rename(first.key, alias: "Main")
        app.move(second.key, before: first.key)
        var reopened = try JSONDecoder().decode(AgentRegistry.self, from: JSONEncoder().encode(app))
        reopened.invalidateEvidence(); reopened.reconcile([first, second])
        XCTAssertEqual(reopened.sessions.map(\.id), [second.key, first.key])
        XCTAssertEqual(reopened.sessions[1].title, "Main")
        XCTAssertEqual(reopened.sessions.map(\.state), [.unknown, .unknown])
    }
    func testMalformedPreferencesRestoreDefaultsAndInvalidWidthIsNormalized() throws {
        XCTAssertFalse(AppPreferences.load(Data("invalid".utf8)).startAtLogin)
        var preferences = AppPreferences(); preferences.panelWidth = -1; preferences.railPosition = 4
        let reopened = AppPreferences.load(try JSONEncoder().encode(preferences))
        XCTAssertEqual(reopened.panelWidth, 360)
        XCTAssertEqual(reopened.railPosition, 1)
        let safe = "cd '/Users/test/it'\\''s folder' && claude -r 00000000-0000-0000-0000-000000000001"
        XCTAssertEqual(ReportDocument(markdown: safe).commands.first?.resume?.directory, "/Users/test/it's folder")
        XCTAssertNil(ReportDocument(markdown: "cd /tmp && codex resume 00000000-0000-0000-0000-000000000001 | bash").commands.first?.resume)
        XCTAssertNil(ReportDocument(markdown: "cd \"$(touch /tmp/file)\" && claude -r 00000000-0000-0000-0000-000000000001").commands.first?.resume)
    }

    func testUncertainResumeConfirmsOnlyRequestedConversationAndCanRecoverWithoutAnotherCreate() throws {
        let requested = "00000000-0000-0000-0000-000000000001"
        let request = try XCTUnwrap(ResumeRequest(provider: .codex, conversation: requested, directory: "/project"))
        let first = AgentCandidate(terminal: .init(id: "new-pane", generation: "101"), provider: .codex, project: "/project", name: "One")
        let second = AgentCandidate(terminal: .init(id: "other-pane", generation: "102"), provider: .codex, project: "/project", name: "Two")
        var app = AgentRegistry(); app.reconcile([first, second])
        app.apply(.init(terminal: first.terminal, provider: .codex, conversation: "00000000-0000-0000-0000-000000000002", sequence: 1, kind: .working, associationProven: true))
        XCTAssertEqual(app.resumeConfirmation(request, createdTerminalID: first.terminal.id), .waiting)
        app.apply(.init(terminal: second.terminal, provider: .codex, conversation: requested, sequence: 2, kind: .working, associationProven: true))
        XCTAssertEqual(app.resumeConfirmation(request, createdTerminalID: first.terminal.id), .waiting)
        XCTAssertEqual(app.resumeConfirmation(request, createdTerminalID: nil), .confirmed(second.key))
        app.apply(.init(terminal: first.terminal, provider: .codex, conversation: requested, sequence: 3, kind: .working, associationProven: true))
        XCTAssertEqual(app.resumeConfirmation(request, createdTerminalID: nil), .choose([first.key, second.key]))
        app.invalidateEvidence()
        XCTAssertEqual(app.resumeConfirmation(request, createdTerminalID: nil), .waiting)
        XCTAssertEqual(app.resumeDecision(request), .create(request))
    }
}
