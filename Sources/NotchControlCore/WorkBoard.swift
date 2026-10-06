import Foundation

/// How a work entry appears in the notch.
public enum WorkMark: Equatable, Sendable {
    /// `AgentSession.id` of the newest listed conversation that runs in an open terminal.
    case open(String)
    /// No listed conversation is open; resuming starts the newest one.
    case closed(ResumeRequest)
    /// The entry lists no session.
    case note
}

public struct WorkItem: Identifiable, Equatable, Sendable {
    public let entry: WorkEntry
    public let mark: WorkMark
    public var id: String { entry.id }
}

/// Work entries in file order, plus the open sessions no entry shows, so a pending decision is never hidden.
public struct WorkBoard: Equatable, Sendable {
    public let items: [WorkItem]
    public let unlisted: [String]
    public init(entries: [WorkEntry], sessions: [AgentSession]) {
        let items = entries.map { entry -> WorkItem in
            let open = entry.sessions.lazy.compactMap { request in
                sessions.first { $0.provider == request.provider && $0.conversation?.lowercased() == request.conversation }
            }.first
            if let open { return WorkItem(entry: entry, mark: .open(open.id)) }
            if let newest = entry.sessions.first { return WorkItem(entry: entry, mark: .closed(newest)) }
            return WorkItem(entry: entry, mark: .note)
        }
        let shown = Set(items.compactMap { item -> String? in
            if case .open(let id) = item.mark { return id }
            return nil
        })
        self.items = items
        unlisted = sessions.map(\.id).filter { !shown.contains($0) }
    }
}
