import Foundation

public struct TerminalIdentity: Codable, Equatable, Sendable {
    public let id: String
    public let generation: String

    public init(id: String, generation: String) {
        self.id = id
        self.generation = generation
    }
}

public struct TerminalInput: Encodable, Equatable, Sendable {
    public let connection: String
    public let terminal: TerminalIdentity
    public let selection: UInt64
    public let text: String
    public let suppressBroadcast = true
}

public enum SessionControlError: Error, Equatable {
    case notConnected
    case noSelection
    case terminalClosed
    case staleInput
}

public struct SessionControl: Sendable {
    public private(set) var connection: String?
    public private(set) var selected: TerminalIdentity?
    private var terminals: [String: TerminalIdentity] = [:]
    private var selection: UInt64 = 0

    public init() {}

    public mutating func reconcile(connection: String, terminals: [TerminalIdentity]) {
        if self.connection != connection {
            selected = nil
            selection &+= 1
        }
        self.connection = connection
        self.terminals = Dictionary(terminals.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        if let selected, self.terminals[selected.id] != selected {
            self.selected = nil
        }
    }

    public mutating func disconnect() {
        connection = nil
        terminals.removeAll()
        selected = nil
        selection &+= 1
    }

    public mutating func deselect() {
        selected = nil
        selection &+= 1
    }

    public mutating func select(_ id: String) throws {
        guard connection != nil else { throw SessionControlError.notConnected }
        guard let terminal = terminals[id] else { throw SessionControlError.terminalClosed }
        selected = terminal
        selection &+= 1
    }

    public func prepareInput(_ text: String) throws -> TerminalInput {
        guard let connection else { throw SessionControlError.notConnected }
        guard let selected else { throw SessionControlError.noSelection }
        guard terminals[selected.id] == selected else { throw SessionControlError.terminalClosed }
        return TerminalInput(connection: connection, terminal: selected, selection: selection, text: text)
    }

    public func validate(_ input: TerminalInput) throws {
        guard input.connection == connection,
              input.terminal == selected,
              input.selection == selection,
              terminals[input.terminal.id] == input.terminal else {
            throw SessionControlError.staleInput
        }
    }

    public func accepts(_ snapshot: TerminalSnapshot) -> Bool {
        snapshot.connection == connection && snapshot.terminal == selected &&
            snapshot.selection == selection && terminals[snapshot.terminal.id] == snapshot.terminal &&
            (2...1000).contains(snapshot.columns) && (1...500).contains(snapshot.rows) &&
            snapshot.lines.count <= snapshot.rows &&
            snapshot.lines.allSatisfy { $0.cells.count <= snapshot.columns }
    }
}
