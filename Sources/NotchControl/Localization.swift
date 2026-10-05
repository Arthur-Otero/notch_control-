import Foundation
import NotchControlCore

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
}
