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

/// One bubble of the notch: the work entries whose session is the same.
public struct WorkItem: Identifiable, Equatable, Sendable {
    /// First of those entries in file order; its title and status represent the bubble.
    public let entry: WorkEntry
    /// The other entries that resolve to the same session, in file order.
    public fileprivate(set) var others: [WorkEntry]
    public let mark: WorkMark
    public var id: String { entry.id }
}

/// Work entries in file order, plus the open sessions no entry shows, so a pending decision is never hidden.
///
/// One session can cover several repositories, so several entries can resolve to the same session: the open one, or
/// the newest one when none is open. Those entries share one item, which makes a session a single bubble whether it
/// is open or closed. A closed session that no entry resolves to stays out, as does a session of an entry that an
/// open or newer one represents.
public struct WorkBoard: Equatable, Sendable {
    public let items: [WorkItem]
    public let unlisted: [String]
    public init(entries: [WorkEntry], sessions: [AgentSession]) {
        var items: [WorkItem] = []
        var position: [String: Int] = [:]
        for entry in entries {
            let open = entry.sessions.lazy.compactMap { request in
                sessions.first { $0.provider == request.provider && $0.conversation?.lowercased() == request.conversation }
            }.first
            let mark: WorkMark
            if let open { mark = .open(open.id) }
            else if let newest = entry.sessions.first { mark = .closed(newest) }
            else { mark = .note }
            guard let key = Self.key(mark) else { items.append(WorkItem(entry: entry, others: [], mark: mark)); continue }
            if let index = position[key] { items[index].others.append(entry) }
            else { position[key] = items.count; items.append(WorkItem(entry: entry, others: [], mark: mark)) }
        }
        let shown = Set(items.compactMap { item -> String? in
            if case .open(let id) = item.mark { return id }
            return nil
        })
        self.items = items
        unlisted = sessions.map(\.id).filter { !shown.contains($0) }
    }

    /// The session a mark points to; a note points to none and never shares its bubble.
    private static func key(_ mark: WorkMark) -> String? {
        switch mark {
        case .open(let id): "open:" + id
        case .closed(let request): "closed:" + request.provider.rawValue + ":" + request.conversation
        case .note: nil
        }
    }
}
