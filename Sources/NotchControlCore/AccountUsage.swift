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

public struct AccountUsageReading: Decodable, Equatable, Sendable {
    public let connection: String
    public let terminal: TerminalIdentity
    public let windows: [AccountUsageWindow]

    public var isValid: Bool {
        windows.count <= 4 && windows.allSatisfy(\.isValid) && Set(windows.map(\.id)).count == windows.count
    }
}
