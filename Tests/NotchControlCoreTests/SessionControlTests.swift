import Testing
import Foundation
import NotchControlCore

@Test func inputRequiresReconciledSelectedTerminal() throws {
    var app = SessionControl()
    #expect(throws: SessionControlError.notConnected) {
        try app.prepareInput("yes\r")
    }
    app.reconcile(connection: "c1", terminals: [TerminalIdentity(id: "t1", generation: "g1")])
    try app.select("t1")
    let input = try app.prepareInput("yes\r")
    #expect(input.terminal == TerminalIdentity(id: "t1", generation: "g1"))
    #expect(input.connection == "c1")
    #expect(input.text == "yes\r")
    #expect(input.suppressBroadcast)
}

@Test func inputPreparedBeforeSwitchCannotReachEitherTerminal() throws {
    var app = SessionControl()
    app.reconcile(connection: "c1", terminals: [
        TerminalIdentity(id: "t1", generation: "g1"),
        TerminalIdentity(id: "t2", generation: "g2")
    ])
    try app.select("t1")
    let oldInput = try app.prepareInput("approve\r")
    try app.select("t2")
    #expect(throws: SessionControlError.staleInput) { try app.validate(oldInput) }
    #expect(try app.prepareInput("hello").terminal.id == "t2")
}

@Test func reconnectDisablesInputUntilInventoryAndRejectsOldRequest() throws {
    var app = SessionControl()
    app.reconcile(connection: "c1", terminals: [TerminalIdentity(id: "t1", generation: "g1")])
    try app.select("t1")
    let oldInput = try app.prepareInput("yes\r")
    app.disconnect()
    #expect(throws: SessionControlError.notConnected) { try app.prepareInput("yes\r") }
    app.reconcile(connection: "c2", terminals: [TerminalIdentity(id: "t1", generation: "g1")])
    #expect(app.selected == nil)
    try app.select("t1")
    #expect(throws: SessionControlError.staleInput) { try app.validate(oldInput) }
}

@Test func terminalScreenCannotOverwriteTheNewSelection() throws {
    var app = SessionControl()
    app.reconcile(connection: "c1", terminals: [
        TerminalIdentity(id: "t1", generation: "g1"),
        TerminalIdentity(id: "t2", generation: "g2")
    ])
    try app.select("t1")
    let request = try app.prepareInput("")
    let snapshot = TerminalSnapshot(
        connection: request.connection, terminal: request.terminal,
        selection: request.selection, columns: 80, rows: 24,
        cursor: TerminalCursor(x: 2, y: 3), lines: []
    )
    #expect(app.accepts(snapshot))
    try app.select("t2")
    #expect(!app.accepts(snapshot))
}

@Test func closingMirrorDisablesInputAndRejectsPendingText() throws {
    var app = SessionControl()
    app.reconcile(connection: "c1", terminals: [TerminalIdentity(id: "t1", generation: "g1")])
    try app.select("t1")
    let pending = try app.prepareInput("yes\r")
    app.deselect()
    #expect(app.selected == nil)
    #expect(throws: SessionControlError.noSelection) { try app.prepareInput("yes\r") }
    #expect(throws: SessionControlError.staleInput) { try app.validate(pending) }
}
