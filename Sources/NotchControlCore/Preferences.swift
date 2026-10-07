import Foundation

public enum InterfaceLanguage: String, Codable, Sendable { case portuguese, english }
/// What an alert does to the notch when it is folded.
public enum AlertNotchAction: String, Codable, Sendable, CaseIterable { case nothing, open, pin }
public struct AlertPreference: Codable, Equatable, Sendable {
    public var notification = true
    public var sound = true
    public var soundName = "Glass"
    /// Optional so preferences saved before the option existed still decode.
    private var notch: AlertNotchAction?
    public var notchAction: AlertNotchAction {
        get { notch ?? .nothing }
        set { notch = newValue }
    }
    public init() {}
}
public struct AppPreferences: Codable, Sendable {
    public var edge: PanelEdge = .right
    public var screenID: UInt32?
    public var railPosition: Double = 0.5
    public var panelWidth: Double = 560
    /// Pinned: the notch never folds by itself. New installs start pinned.
    public var alwaysVisible = true
    public var language: InterfaceLanguage = Locale.preferredLanguages.first?.hasPrefix("pt") == true ? .portuguese : .english
    public var workPath: String?
    public var historyPath: String?
    public var waiting = AlertPreference()
    public var completed = AlertPreference()
    public var startAtLogin = false
    /// Optional so preferences saved before the option existed still decode.
    private var workMode: Bool?
    public var showsWorkEntries: Bool {
        get { workMode ?? false }
        set { workMode = newValue }
    }
    public init() {}
    public mutating func normalize() {
        railPosition = railPosition.isFinite ? min(1, max(0, railPosition)) : 0.5
        panelWidth = panelWidth.isFinite ? max(360, min(4000, panelWidth)) : 560
        for key in [\Self.waiting, \Self.completed] {
            if !["Glass", "Ping", "Pop", "Basso", "Submarine"].contains(self[keyPath: key].soundName) { self[keyPath: key].soundName = "Glass" }
        }
    }
    public static func load(_ data: Data?) -> AppPreferences {
        guard let data, var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        value.normalize(); return value
    }
}
public enum AlertKind: String, Sendable { case waiting, completed }
public struct AlertTracker: Sendable {
    private var seen: [String: (AgentState, UInt64)] = [:]
    public init() {}
    public mutating func reset() { seen.removeAll() }
    public mutating func observe(id: String, state: AgentState, sequence: UInt64, kind: AgentEventKind, baseline: Bool = false) -> AlertKind? {
        let previous = seen[id]
        guard previous.map({ sequence > $0.1 }) ?? true else { return nil }
        seen[id] = (state, sequence)
        guard !baseline, let previous else { return nil }
        if state == .waiting, previous.0 != .waiting { return .waiting }
        if state == .idle, kind == .completed, previous.0 == .working || previous.0 == .waiting { return .completed }
        return nil
    }
}
