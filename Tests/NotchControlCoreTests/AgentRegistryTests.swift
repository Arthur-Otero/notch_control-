import XCTest
@testable import NotchControlCore

final class AgentRegistryTests: XCTestCase {
    func testTwoAgentsInSameProjectKeepSeparateStatesAndRejectOldProcess() {
        var app = AgentRegistry()
        let a = AgentCandidate(terminal: .init(id: "a", generation: "101"), provider: .codex, project: "/same", name: "A")
        let b = AgentCandidate(terminal: .init(id: "b", generation: "102"), provider: .codex, project: "/same", name: "B")
        app.reconcile([a, b])
        app.apply(.init(terminal: a.terminal, provider: .codex, conversation: "conversation-a", sequence: 1, kind: .waiting, reason: "approval", associationProven: true))
        XCTAssertEqual(app.sessions.map(\.state), [.waiting, .unknown])
        app.apply(.init(terminal: b.terminal, provider: .codex, conversation: "conversation-a", sequence: 2, kind: .working, associationProven: false))
        XCTAssertEqual(app.sessions[1].state, .unknown)
        app.reconcile([.init(terminal: .init(id: "a", generation: "201"), provider: .codex, project: "/same", name: "A"), b])
        app.apply(.init(terminal: a.terminal, provider: .codex, conversation: "conversation-a", sequence: 3, kind: .waiting, associationProven: true))
        XCTAssertEqual(app.sessions.map(\.state), [.unknown, .unknown])
        XCTAssertEqual(app.sessions.map(\.id), [b.key, "codex:a:201"])
    }

    /// Sessions carry no number: it only counted instances since the first launch and meant nothing to the user.
    func testSavedRegistryHasNoSessionNumberAndOldFilesStillLoad() throws {
        var app = AgentRegistry()
        app.reconcile([AgentCandidate(terminal: .init(id: "a", generation: "1"), provider: .claude, project: "/p", name: "A")])
        let saved = try XCTUnwrap(String(data: JSONEncoder().encode(app), encoding: .utf8))
        XCTAssertFalse(saved.contains("number"), saved)
        XCTAssertFalse(saved.contains("Number"), saved)

        let legacy = Data(#"{"nextNumber":35,"sessions":[{"id":"claude:a:1","provider":"claude","number":33,"name":"A","project":"/p","state":"unknown","sequence":0,"terminal":{"id":"a","generation":"1"}}]}"#.utf8)
        let loaded = try JSONDecoder().decode(AgentRegistry.self, from: legacy)
        XCTAssertEqual(loaded.sessions.map(\.id), ["claude:a:1"])
    }

    func testCursorSessionsJoinTheRegistryAndTitlesDropTerminalNoise() {
        var app = AgentRegistry()
        let cursor = AgentCandidate(terminal: .init(id: "c", generation: "1"), provider: .cursor, project: "/Users/me/notch_control", name: "Design E Funcionalidade (agent)")
        let claude = AgentCandidate(terminal: .init(id: "d", generation: "2"), provider: .claude, project: "/Users/me", name: "✳ Claude Code (claude)")
        let codex = AgentCandidate(terminal: .init(id: "e", generation: "3"), provider: .codex, project: "/Users/me", name: "Responder ao cumprimento | arthu (codex)")
        let bare = AgentCandidate(terminal: .init(id: "f", generation: "4"), provider: .codex, project: "/Users/me", name: "✳ (codex)")
        app.reconcile([cursor, claude, codex, bare])
        XCTAssertEqual(app.sessions.map(\.provider), [.cursor, .claude, .codex, .codex])
        XCTAssertEqual(app.sessions.map(\.title), ["Design E Funcionalidade", "Claude Code", "Responder ao cumprimento | arthu", "Codex"])
        XCTAssertEqual(app.sessions[0].projectName, "notch_control")
        XCTAssertEqual(AgentProvider.allCases.map(\.displayName), ["Claude Code", "Codex", "Cursor"])
        let reloaded = try? JSONDecoder().decode(AgentRegistry.self, from: JSONEncoder().encode(app))
        XCTAssertEqual(reloaded?.sessions.first?.provider, .cursor)
    }
}
