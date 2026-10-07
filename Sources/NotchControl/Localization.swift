import Foundation
import NotchControlCore

extension NotchVisibility {
    var titleKey: String {
        switch self {
        case .alwaysOpen: "visibility_open"
        case .automatic: "visibility_automatic"
        case .alwaysFolded: "visibility_folded"
        }
    }
    var hintKey: String { titleKey + "_hint" }
}

struct Messages {
    let language: InterfaceLanguage
    func text(_ key: String) -> String {
        let name = language == .portuguese ? "pt-BR" : "en"
        let resources = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("NotchControl_NotchControl.bundle")) } ?? Bundle.module
        let locale = resources.localizations.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
        let bundle = resources.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("\(locale).lproj")) } ?? resources
        let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        return value == key ? bundle.localizedString(forKey: "api_operation_failed", value: nil, table: "Localizable") : value
    }
    /// How many more work entries share the bubble's session, as in "+3 in the same session".
    func sharedSession(_ count: Int) -> String { "+\(count) " + text("work_also") }
    /// Accessible name of a work bubble: its title, plus how many more entries share the session.
    func title(of item: WorkItem) -> String {
        item.others.isEmpty ? item.entry.title : item.entry.title + ", " + sharedSession(item.others.count)
    }
}
