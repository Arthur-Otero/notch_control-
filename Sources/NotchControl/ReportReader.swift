import Combine
import Foundation
import NotchControlCore

@MainActor
final class ReportReader: ObservableObject {
    @Published private(set) var document = ReportDocument(markdown: "")
    @Published private(set) var errorKey: String?
    @Published private(set) var isLoading = false
    private var reader = ReportFileReader(path: nil)
    private var timer: Timer?
    func open(_ path: String?) {
        timer?.invalidate()
        reader = ReportFileReader(path: path)
        document = ReportDocument(markdown: ""); errorKey = nil
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func refresh() {
        reader.refresh()
        if document.markdown != reader.document.markdown { document = reader.document }
        errorKey = reader.errorKey
        isLoading = reader.isLoading
    }
}
