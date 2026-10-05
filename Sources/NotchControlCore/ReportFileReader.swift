import Foundation

public struct ReportFileReader: Sendable {
    public private(set) var document = ReportDocument(markdown: "")
    public private(set) var errorKey: String?
    public private(set) var isLoading: Bool
    private let path: String?
    private var signature: String?
    private var loadedSignature: String?

    public init(path: String?) { self.path = path; isLoading = path != nil }

    public mutating func refresh() {
        guard let path else { return }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let current = "\(attrs[.modificationDate] ?? ""):\(attrs[.size] ?? ""):\(attrs[.systemFileNumber] ?? "")"
            guard current == signature else { signature = current; isLoading = true; return }
            guard loadedSignature != current else { return }
            guard let size = attrs[.size] as? NSNumber, size.intValue <= 10 * 1024 * 1024 else { isLoading = false; errorKey = "read_failed"; return }
            let text = try String(contentsOfFile: path, encoding: .utf8)
            let after = try FileManager.default.attributesOfItem(atPath: path)
            guard attrs[.modificationDate] as? Date == after[.modificationDate] as? Date,
                  attrs[.size] as? NSNumber == after[.size] as? NSNumber,
                  attrs[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber else { return }
            document = ReportDocument(markdown: text); loadedSignature = current; errorKey = nil; isLoading = false
        } catch {
            signature = nil; loadedSignature = nil
            isLoading = false
            errorKey = document.markdown.isEmpty ? "file_unavailable" : "read_failed"
        }
    }
}
