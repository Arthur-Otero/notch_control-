import Foundation

public struct AccountUsageWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let usedPercent: Double
    public let resetHint: String?

    public init(id: String, usedPercent: Double, resetHint: String? = nil) {
        self.id = id
        self.usedPercent = usedPercent
        self.resetHint = resetHint
    }

    public var isValid: Bool {
        ["five_hour", "seven_day", "cursor", "other_models"].contains(id)
            && usedPercent.isFinite && (0...100).contains(usedPercent)
            && (resetHint?.count ?? 0) <= 32
    }
}

/// Share of the context window one session uses, as its status bar reports it; nil once the reading expires.
public struct ContextUsageReading: Decodable, Equatable, Sendable {
    public let connection: String
    public let terminal: TerminalIdentity
    public let usedPercent: Double?

    public init(connection: String, terminal: TerminalIdentity, usedPercent: Double?) {
        self.connection = connection
        self.terminal = terminal
        self.usedPercent = usedPercent
    }

    public var isValid: Bool { usedPercent.map { $0.isFinite && (0...100).contains($0) } ?? true }
}

public enum UsageLevel: Equatable, Sendable {
    case low, medium, high
    /// Context window: medium from 30%, high from 70%.
    public static func context(_ usedPercent: Double) -> Self { level(usedPercent, medium: 30, high: 70) }
    /// Account limits: medium from 50%, high from 80%.
    public static func account(_ usedPercent: Double) -> Self { level(usedPercent, medium: 50, high: 80) }
    private static func level(_ usedPercent: Double, medium: Double, high: Double) -> Self {
        usedPercent < medium ? .low : usedPercent < high ? .medium : .high
    }
}

public struct AccountUsageReading: Decodable, Equatable, Sendable {
    public let connection: String
    public let terminal: TerminalIdentity
    public let windows: [AccountUsageWindow]

    public var isValid: Bool {
        windows.count <= 4 && windows.allSatisfy(\.isValid) && Set(windows.map(\.id)).count == windows.count
    }
}
