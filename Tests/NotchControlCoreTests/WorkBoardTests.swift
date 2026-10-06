import XCTest
@testable import NotchControlCore

final class WorkBoardTests: XCTestCase {
    private let newest = "00000000-0000-0000-0000-00000000000a"
    private let older = "00000000-0000-0000-0000-00000000000b"
    private let other = "00000000-0000-0000-0000-00000000000c"
    private var markdown: String {
        """
        # Work

        ## 2026-09-30 18:40 — #123 Paywall novo
        - Início: 2026-09-25 10:12
        - Sessões:
          - 2026-09-30 · gpt-6-sol
            cd '/Users/test/My Lib' && codex resume \(newest)
          - 2026-09-25 · Opus 5.5
            `cd /Users/test/app && claude -r \(older.uppercased())`
        - Status: Lib pronta no PR #45; falta integrar no app.

        ## 2026-09-29 10:00 — Revisar PR do time
        - Início: 2026-09-29 10:00
        - Status:

        ## 2026-09-28 — Revisar PR do time
        - Sessões:
          - 2026-09-28 · Opus 5.5
            cd /Users/test/other && claude -r \(other)
        """
    }

    func testEntriesFollowTheFileWithTitlesWithoutDatesAndSessionsNewestFirst() {
        let entries = ReportDocument(markdown: markdown).entries
        XCTAssertEqual(entries.map(\.title), ["#123 Paywall novo", "Revisar PR do time", "Revisar PR do time"])
        XCTAssertEqual(entries.map(\.id), ["work:#123 Paywall novo", "work:Revisar PR do time", "work:Revisar PR do time#2"])
        XCTAssertEqual(entries[0].status, "Lib pronta no PR #45; falta integrar no app.")
        XCTAssertNil(entries[1].status)
        XCTAssertEqual(entries[0].sessions.map(\.provider), [.codex, .claude])
        XCTAssertEqual(entries[0].sessions.map(\.conversation), [newest, older])
        XCTAssertEqual(entries[0].sessions.first?.directory, "/Users/test/My Lib")
        XCTAssertEqual(entries[1].sessions, [])
        XCTAssertEqual(ReportDocument(markdown: "# Work\ncd /tmp && claude -r \(newest)").entries, [])
    }

    func testOpenEntriesShowTheirNewestOpenSessionAndClosedOnesResumeTheNewest() throws {
        let entries = ReportDocument(markdown: markdown).entries
        var registry = AgentRegistry()
        registry.reconcile([session("a", .claude, older), session("b", .claude, other), session("c", .codex, nil)])
        let board = WorkBoard(entries: entries, sessions: registry.sessions)
        // The newest (Codex) is closed, so the older open Claude session represents the entry.
        XCTAssertEqual(board.items[0].mark, .open("claude:a:1"))
        XCTAssertEqual(board.items[1].mark, .note)
        XCTAssertEqual(board.items[2].mark, .open("claude:b:1"))
        XCTAssertEqual(board.unlisted, ["codex:c:1"])

        registry.reconcile([session("b", .claude, other)])
        let closed = WorkBoard(entries: entries, sessions: registry.sessions)
        XCTAssertEqual(closed.items[0].mark, .closed(try XCTUnwrap(ResumeRequest(provider: .codex, conversation: newest, directory: "/Users/test/My Lib"))))
        XCTAssertEqual(closed.unlisted, [])
    }

    func testOnlyTheSameProviderAndConversationMatchAndExtraOpenCopiesStayVisible() {
        let entries = ReportDocument(markdown: markdown).entries
        var registry = AgentRegistry()
        registry.reconcile([session("a", .codex, older), session("b", .claude, other), session("d", .claude, other)])
        let board = WorkBoard(entries: entries, sessions: registry.sessions)
        if case .closed = board.items[0].mark {} else { XCTFail("A Codex terminal must not answer for a Claude conversation") }
        XCTAssertEqual(board.items[2].mark, .open("claude:b:1"))
        XCTAssertEqual(board.unlisted, ["codex:a:1", "claude:d:1"])
    }

    /// One session works across several repositories, so each entry lists it. V1 and V2 list the session in use and the
    /// previous one, which is closed; the two apps were last worked on in the previous one.
    private var sharedEntries: [WorkEntry] {
        entries([("V1", [newest, older]), ("V2", [newest, older]), ("App A", [older]), ("App B", [older]), ("Solta", [other]), ("Nota", [])])
    }

    func testEachSessionIsOneBubbleWhetherOpenOrClosedAndSharingEntriesJoinIt() throws {
        var registry = AgentRegistry()
        registry.reconcile([session("a", .claude, newest), session("b", .claude, other)])
        let board = WorkBoard(entries: sharedEntries, sessions: registry.sessions)
        XCTAssertEqual(board.items.map(\.entry.title), ["V1", "App A", "Solta", "Nota"])
        XCTAssertEqual(board.items.map { $0.others.map(\.title) }, [["V2"], ["App B"], [], []])
        // The session in use points to its tab; the previous one is closed and stays a bubble that resumes it.
        XCTAssertEqual(board.items.map(\.mark), [
            .open("claude:a:1"),
            .closed(try XCTUnwrap(ResumeRequest(provider: .claude, conversation: older, directory: "/Users/test/app"))),
            .open("claude:b:1"),
            .note
        ])
        XCTAssertEqual(board.items.map(\.id), ["work:V1", "work:App A", "work:Solta", "work:Nota"])
        XCTAssertEqual(board.unlisted, [])
        // No session in two bubbles, whether it comes from an entry or from outside the file.
        let ids = board.items.compactMap { item -> String? in
            switch item.mark {
            case .open(let id): id
            case .closed(let request): request.provider.rawValue + ":" + request.conversation
            case .note: nil
            }
        } + board.unlisted
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testWithoutAnyOpenTerminalEachNewestSessionResumesFromOneBubble() throws {
        let board = WorkBoard(entries: sharedEntries, sessions: [])
        XCTAssertEqual(board.items.map(\.entry.title), ["V1", "App A", "Solta", "Nota"])
        XCTAssertEqual(board.items.map { $0.others.map(\.title) }, [["V2"], ["App B"], [], []])
        XCTAssertEqual(board.items[0].mark, .closed(try XCTUnwrap(ResumeRequest(provider: .claude, conversation: newest, directory: "/Users/test/app"))))
        XCTAssertEqual(board.items[1].mark, .closed(try XCTUnwrap(ResumeRequest(provider: .claude, conversation: older, directory: "/Users/test/app"))))
    }

    func testAnOlderOpenSessionRepresentsItsEntryAndJoinsTheEntriesThatListOnlyIt() {
        var registry = AgentRegistry()
        registry.reconcile([session("old", .claude, older)])
        let board = WorkBoard(entries: sharedEntries, sessions: registry.sessions)
        // V1 and V2 list a newer closed session too, but the open one wins, so all four entries share its tab.
        XCTAssertEqual(board.items[0].mark, .open("claude:old:1"))
        XCTAssertEqual(board.items[0].others.map(\.title), ["V2", "App A", "App B"])
        XCTAssertEqual(board.items.map(\.entry.title), ["V1", "Solta", "Nota"])
        XCTAssertEqual(board.unlisted, [])
    }

    func testASecondOpenSessionOfTheSameConversationStaysVisibleOutsideTheBubble() {
        var registry = AgentRegistry()
        registry.reconcile([session("a", .claude, newest), session("copy", .claude, newest)])
        let board = WorkBoard(entries: sharedEntries, sessions: registry.sessions)
        XCTAssertEqual(board.items[0].mark, .open("claude:a:1"))
        XCTAssertEqual(board.unlisted, ["claude:copy:1"])
    }

    func testEntriesWithDifferentSessionsAndNotesStayApart() {
        let separate = entries([("A", [newest]), ("B", [older]), ("C", []), ("D", [])])
        let board = WorkBoard(entries: separate, sessions: [])
        XCTAssertEqual(board.items.map(\.entry.title), ["A", "B", "C", "D"])
        XCTAssertTrue(board.items.allSatisfy { $0.others.isEmpty })
    }

    func testInventoryConversationReplacesTheStoredOneButAMissingOneKeepsTheHookProof() {
        var registry = AgentRegistry()
        let terminal = TerminalIdentity(id: "a", generation: "1")
        registry.reconcile([session("a", .claude, nil)])
        registry.apply(.init(terminal: terminal, provider: .claude, conversation: older, sequence: 1, kind: .working, associationProven: true))
        registry.reconcile([session("a", .claude, nil)])
        XCTAssertEqual(registry.sessions.first?.conversation, older)
        registry.reconcile([session("a", .claude, newest.uppercased())])
        XCTAssertEqual(registry.sessions.first?.conversation, newest)
    }

    func testPreferencesSavedBeforeTheWorkModeStillLoad() throws {
        var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppPreferences())) as? [String: Any] ?? [:]
        saved["workMode"] = nil
        saved["edge"] = "left"
        saved["panelWidth"] = 777
        let loaded = AppPreferences.load(try JSONSerialization.data(withJSONObject: saved))
        XCTAssertEqual(loaded.edge, .left)
        XCTAssertEqual(loaded.panelWidth, 777)
        XCTAssertFalse(loaded.showsWorkEntries)
        var enabled = loaded
        enabled.showsWorkEntries = true
        XCTAssertTrue(AppPreferences.load(try JSONEncoder().encode(enabled)).showsWorkEntries)
    }

    private func entries(_ spec: [(title: String, conversations: [String])]) -> [WorkEntry] {
        ReportDocument(markdown: spec.map { entry in
            "## 2026-10-06 — \(entry.title)\n- Sessões:\n" + entry.conversations.map {
                "  - 2026-10-06 · Opus 5.5\n    cd /Users/test/app && claude -r \($0)"
            }.joined(separator: "\n")
        }.joined(separator: "\n\n")).entries
    }

    private func session(_ id: String, _ provider: AgentProvider, _ conversation: String?) -> AgentCandidate {
        AgentCandidate(terminal: .init(id: id, generation: "1"), provider: provider, project: "/project", name: id, conversation: conversation)
    }
}
