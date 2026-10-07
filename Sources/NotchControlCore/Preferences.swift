import Foundation

public enum InterfaceLanguage: String, Codable, Sendable { case portuguese, english }
/// What an alert does to the notch when it is folded. `pin` turns the pin on.
public enum AlertNotchAction: String, Codable, Sendable, CaseIterable { case nothing, open, pin }
/// When the notch folds into the pill, from most to least visible, while the pin is off.
/// Hovering or clicking the pill always opens it.
public enum NotchVisibility: String, Codable, Sendable, CaseIterable {
    /// Never folds by itself.
    case alwaysOpen
    /// Open while some session works, waits for a decision or holds a result not seen yet; folded once all are idle.
    case automatic
    /// Folds as soon as the pointer leaves, even with sessions working or waiting.
    case alwaysFolded
    public func holdsOpen(attention: AgentState?) -> Bool {
        switch self {
        case .alwaysOpen: true
        case .automatic: attention != nil
        case .alwaysFolded: false
        }
    }
}
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
    /// Pin state, switched by the pin on the notch: while on, the notch never folds by itself and `notchVisibility`
    /// is ignored. New installs start pinned.
    public var alwaysVisible = true
    /// Optional so preferences saved before the option existed still decode.
    private var pinShown: Bool?
    /// Whether the pin is on the notch. Hidden, it can no longer be switched, so it holds nothing open.
    public var showsPin: Bool {
        get { pinShown ?? true }
        set { pinShown = newValue }
    }
    public var pinHoldsOpen: Bool { showsPin && alwaysVisible }
    /// Optional so preferences saved before the option existed still decode.
    private var visibility: NotchVisibility?
    public var notchVisibility: NotchVisibility {
        get { visibility ?? .automatic }
        set { visibility = newValue }
    }
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
        visibility = notchVisibility  // saved explicitly, so unpinning later cannot change what the notch does
        railPosition = railPosition.isFinite ? min(1, max(0, railPosition)) : 0.5
        panelWidth = panelWidth.isFinite ? max(360, min(4000, panelWidth)) : 560
        for key in [\Self.waiting, \Self.completed] {
            if !["Glass", "Ping", "Pop", "Basso", "Submarine"].contains(self[keyPath: key].soundName) { self[keyPath: key].soundName = "Glass" }
        }
    }
    public static func load(_ data: Data?) -> AppPreferences {
        guard let data, var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        // Saved before the visibility existed, an unpinned notch folded as soon as the pointer left.
        if value.visibility == nil, !value.alwaysVisible { value.visibility = .alwaysFolded }
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
