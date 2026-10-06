import Foundation

public enum AgentProvider: String, Codable, Sendable, CaseIterable {
    case claude, codex, cursor
    /// Nome de produto exibido ao usuário.
    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}
public enum AgentState: String, Codable, Sendable { case working, idle, waiting, unknown }
public enum AgentEventKind: String, Codable, Sendable { case working, waiting, completed, interrupted, unavailable }

public struct AgentCandidate: Equatable, Sendable {
    public let terminal: TerminalIdentity
    public let provider: AgentProvider
    public let project: String
    public let name: String
    public let conversation: String?
    public var key: String { provider.rawValue + ":" + terminal.id + ":" + terminal.generation }
    public init(terminal: TerminalIdentity, provider: AgentProvider, project: String, name: String, conversation: String? = nil) {
        self.terminal = terminal; self.provider = provider; self.project = project; self.name = name
        self.conversation = conversation?.lowercased()
    }
}

public struct AgentEvidence: Codable, Sendable {
    public let terminal: TerminalIdentity
    public let provider: AgentProvider
    public let conversation: String?
    public let sequence: UInt64
    public let kind: AgentEventKind
    public let reason: String?
    public let associationProven: Bool
    public let observedAt: Date
    public let source: String
    public init(terminal: TerminalIdentity, provider: AgentProvider, conversation: String?, sequence: UInt64,
                kind: AgentEventKind, reason: String? = nil, associationProven: Bool, observedAt: Date = Date(), source: String = "structured") {
        self.terminal = terminal; self.provider = provider; self.conversation = conversation
        self.sequence = sequence; self.kind = kind; self.reason = reason
        self.associationProven = associationProven; self.observedAt = observedAt; self.source = source
    }
}

public struct AgentSession: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let terminal: TerminalIdentity
    public let provider: AgentProvider
    public var name: String
    public var project: String
    public var alias: String?
    public var conversation: String?
    public var state: AgentState = .unknown
    public var reason: String?
    public var sequence: UInt64 = 0
    public var observedAt: Date?
    public var source: String?
    /// Finished turn waiting for another prompt. Not saved: opening the terminal clears it.
    public var unseenResult = false
    private enum CodingKeys: String, CodingKey {
        case id, terminal, provider, name, project, alias, conversation, state, reason, sequence, observedAt, source
    }
    /// Apelido do usuário ou o título do terminal sem ruído: o iTerm2 acrescenta o processo entre parênteses
    /// ("Tarefa (claude)") e o Claude Code prefixa um símbolo de atividade ("✳ Claude Code").
    public var title: String {
        if let alias, !alias.isEmpty { return alias }
        var value = name
        if let suffix = value.range(of: #"\s*\([^()]*\)\s*$"#, options: .regularExpression) { value.removeSubrange(suffix) }
        value = String(value.drop { !$0.isLetter && !$0.isNumber }).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? provider.displayName : value
    }
    /// Nome da pasta do projeto, usado como contexto secundário.
    public var projectName: String { URL(fileURLWithPath: project).lastPathComponent }
}

public struct AgentRegistry: Codable, Sendable {
    public private(set) var sessions: [AgentSession] = []
    public init() {}

    /// A candidate without a conversation keeps the one a hook already proved.
    public mutating func reconcile(_ candidates: [AgentCandidate]) {
        let keys = Set(candidates.map(\.key))
        sessions.removeAll { !keys.contains($0.id) }
        for candidate in candidates {
            if let i = sessions.firstIndex(where: { $0.id == candidate.key }) {
                sessions[i].name = candidate.name; sessions[i].project = candidate.project
                sessions[i].conversation = candidate.conversation ?? sessions[i].conversation
            } else {
                sessions.append(AgentSession(id: candidate.key, terminal: candidate.terminal, provider: candidate.provider,
                                             name: candidate.name, project: candidate.project, conversation: candidate.conversation))
            }
        }
    }

    @discardableResult public mutating func apply(_ evidence: AgentEvidence) -> AgentSession? {
        guard evidence.associationProven,
              let i = sessions.firstIndex(where: { $0.terminal == evidence.terminal && $0.provider == evidence.provider }),
              evidence.sequence > sessions[i].sequence,
              sessions[i].observedAt.map({ evidence.observedAt >= $0 }) ?? true else { return nil }
        sessions[i].sequence = evidence.sequence; sessions[i].observedAt = evidence.observedAt
        sessions[i].conversation = evidence.conversation ?? sessions[i].conversation
        sessions[i].source = evidence.source
        sessions[i].reason = evidence.kind == .waiting ? evidence.reason : nil
        switch evidence.kind {
        case .working:
            sessions[i].state = .working
            sessions[i].unseenResult = false
        case .waiting:
            sessions[i].state = .waiting
            sessions[i].unseenResult = false
        case .completed:
            sessions[i].state = .idle
            sessions[i].unseenResult = evidence.reason == "result"
        case .interrupted:
            sessions[i].state = .idle
            sessions[i].unseenResult = false
        case .unavailable:
            sessions[i].state = .unknown
            sessions[i].unseenResult = false
        }
        return sessions[i]
    }

    public mutating func invalidateEvidence() {
        for i in sessions.indices {
            sessions[i].state = .unknown
            sessions[i].reason = nil
            sessions[i].sequence = 0
            sessions[i].observedAt = nil
            sessions[i].unseenResult = false
        }
    }
    /// The user opened this terminal, so a finished turn no longer needs the green mark.
    public mutating func acknowledge(_ id: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].unseenResult = false
    }
    public mutating func rename(_ id: String, alias: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].alias = String(alias.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
    }
    public mutating func move(_ id: String, before other: String?) {
        guard let i = sessions.firstIndex(where: { $0.id == id }), id != other else { return }
        let value = sessions.remove(at: i)
        let destination = other.flatMap { key in sessions.firstIndex { $0.id == key } } ?? sessions.count
        sessions.insert(value, at: destination)
    }
}
