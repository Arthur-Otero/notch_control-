import Foundation

/// When to restart the iTerm2 helper after it stops. The app may be opened long before iTerm2 (or iTerm2 may be
/// restarted), so the wait is bounded but the attempts never run out.
public enum ReconnectPolicy {
    public static let maximumDelay: TimeInterval = 30

    public static func delay(afterFailures failures: Int) -> TimeInterval {
        min(maximumDelay, Double(max(failures, 1)) * 2)
    }
}
