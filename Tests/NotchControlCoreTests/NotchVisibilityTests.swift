import XCTest
@testable import NotchControlCore

final class NotchVisibilityTests: XCTestCase {
    func testEachModeDecidesFromTheMostUrgentSessionState() {
        let attention: [AgentState?] = [nil, .working, .waiting]
        XCTAssertEqual(attention.map(NotchVisibility.alwaysOpen.holdsOpen), [true, true, true])
        XCTAssertEqual(attention.map(NotchVisibility.automatic.holdsOpen), [false, true, true])
        XCTAssertEqual(attention.map(NotchVisibility.alwaysFolded.holdsOpen), [false, false, false])
        XCTAssertEqual(NotchVisibility.allCases, [.alwaysOpen, .automatic, .alwaysFolded], "From most to least visible")
    }

    func testAutomaticFoldsWhenEverySessionIsIdleOrUnrecognized() {
        var registry = AgentRegistry()
        let candidates = [
            AgentCandidate(terminal: .init(id: "one", generation: "test"), provider: .claude, project: "/project", name: "Claude"),
            AgentCandidate(terminal: .init(id: "two", generation: "test"), provider: .codex, project: "/project", name: "Codex")
        ]
        registry.reconcile(candidates)
        XCTAssertFalse(NotchVisibility.automatic.holdsOpen(attention: registry.attention), "Unrecognized screens do not hold it open")
        registry.apply(AgentEvidence(terminal: candidates[0].terminal, provider: .claude, conversation: nil, sequence: 1, kind: .completed, reason: "result", associationProven: true))
        XCTAssertTrue(NotchVisibility.automatic.holdsOpen(attention: registry.attention), "A result not seen yet")
        registry.acknowledge(candidates[0].key)
        XCTAssertFalse(NotchVisibility.automatic.holdsOpen(attention: registry.attention))
        registry.apply(AgentEvidence(terminal: candidates[1].terminal, provider: .codex, conversation: nil, sequence: 1, kind: .waiting, reason: "approval", associationProven: true))
        XCTAssertTrue(NotchVisibility.automatic.holdsOpen(attention: registry.attention), "A pending decision")
    }

    func testNewInstallsStartPinnedAndAutomatic() {
        let preferences = AppPreferences()
        XCTAssertTrue(preferences.alwaysVisible)
        XCTAssertEqual(preferences.notchVisibility, .automatic)
        let loaded = AppPreferences.load(nil)
        XCTAssertTrue(loaded.alwaysVisible)
        XCTAssertEqual(loaded.notchVisibility, .automatic)
    }

    func testPreferencesSavedBeforeTheVisibilityKeepTheirBehavior() throws {
        func loaded(pin: Bool?, visibility: String? = nil) throws -> AppPreferences {
            var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppPreferences())) as? [String: Any] ?? [:]
            saved["visibility"] = visibility
            saved["alwaysVisible"] = pin
            return AppPreferences.load(try JSONSerialization.data(withJSONObject: saved))
        }
        let pinned = try loaded(pin: true)
        XCTAssertTrue(pinned.alwaysVisible)
        XCTAssertEqual(pinned.notchVisibility, .automatic)
        let unpinned = try loaded(pin: false)
        XCTAssertFalse(unpinned.alwaysVisible)
        XCTAssertEqual(unpinned.notchVisibility, .alwaysFolded, "An unpinned notch folded as soon as the pointer left")
        let chosen = try loaded(pin: false, visibility: "alwaysOpen")
        XCTAssertFalse(chosen.alwaysVisible)
        XCTAssertEqual(chosen.notchVisibility, .alwaysOpen, "A saved choice wins")
    }

    func testHidingThePinStopsItHoldingTheNotchOpenAndKeepsItsState() throws {
        var preferences = AppPreferences()
        XCTAssertTrue(preferences.showsPin, "Shown by default")
        XCTAssertTrue(preferences.pinHoldsOpen)
        preferences.showsPin = false
        XCTAssertFalse(preferences.pinHoldsOpen)
        XCTAssertTrue(preferences.alwaysVisible, "The pin state survives while it is hidden")
        var reloaded = AppPreferences.load(try JSONEncoder().encode(preferences))
        XCTAssertFalse(reloaded.showsPin)
        XCTAssertTrue(reloaded.alwaysVisible)
        reloaded.showsPin = true
        XCTAssertTrue(reloaded.pinHoldsOpen, "Showing it again brings back what it was")
        reloaded.alwaysVisible = false
        XCTAssertFalse(reloaded.pinHoldsOpen, "Shown but unpinned")

        var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppPreferences())) as? [String: Any] ?? [:]
        saved["pinShown"] = nil
        XCTAssertTrue(AppPreferences.load(try JSONSerialization.data(withJSONObject: saved)).showsPin, "Saved before the option existed")
    }

    func testTheVisibilityIsSavedSoUnpinningNeverChangesIt() throws {
        var preferences = AppPreferences.load(nil)
        preferences.alwaysVisible = false
        preferences.normalize()
        let reloaded = AppPreferences.load(try JSONEncoder().encode(preferences))
        XCTAssertFalse(reloaded.alwaysVisible)
        XCTAssertEqual(reloaded.notchVisibility, .automatic, "Not mistaken for a notch saved by the old unpinned behavior")

        var chosen = reloaded
        chosen.notchVisibility = .alwaysFolded
        chosen.alwaysVisible = true
        let again = AppPreferences.load(try JSONEncoder().encode(chosen))
        XCTAssertTrue(again.alwaysVisible)
        XCTAssertEqual(again.notchVisibility, .alwaysFolded)
    }
}
