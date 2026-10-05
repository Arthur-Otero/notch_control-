import Foundation
import NotchControlUI
import SwiftUI

struct ReportPanel: View {
    @ObservedObject var store: AppStore
    private var m: Messages { store.messages }
    private var path: String? { store.historyTab ? store.preferences.historyPath : store.preferences.workPath }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.regular) {
                Picker(m.text("report"), selection: $store.historyTab) {
                    Text(m.text("work")).tag(false)
                    Text(m.text("history")).tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 230)
                Spacer(minLength: 0)
                if path != nil {
                    Button { store.chooseFile(history: store.historyTab) } label: {
                        Image(systemName: "folder").frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(m.text("change_file")).accessibilityLabel(m.text("change_file"))
                }
            }.padding(.horizontal, DesignTokens.content).padding(.vertical, DesignTokens.regular)
            if let path {
                HStack(spacing: DesignTokens.compact) {
                    Image(systemName: "doc.text")
                    Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }.font(.system(size: 11)).foregroundStyle(DesignTokens.muted)
                    .padding(.horizontal, DesignTokens.content).padding(.bottom, DesignTokens.compact)
                    .help(path)
            }
            ReportPage(reader: store.historyTab ? store.history : store.work, store: store, path: path)
                .id(store.historyTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ReportPage: View {
    @ObservedObject var reader: ReportReader
    @ObservedObject var store: AppStore
    let path: String?
    private var m: Messages { store.messages }

    var body: some View {
        VStack(spacing: 0) {
            if let error = reader.errorKey, !reader.document.markdown.isEmpty {
                Label(m.text(error), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(DesignTokens.danger)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(DesignTokens.content)
            }
            if !reader.document.markdown.isEmpty {
                MarkdownReader(markdown: reader.document.markdown, documentID: path ?? "",
                               accessibilityLabel: m.text("markdown_document"))
            } else if reader.isLoading {
                ProgressView(m.text("reading_report"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: DesignTokens.content) {
                    Image(systemName: reader.errorKey == nil ? "doc.text" : "doc.badge.ellipsis")
                        .font(.system(size: 32, weight: .light)).foregroundStyle(DesignTokens.muted).accessibilityHidden(true)
                    Text(m.text("reader_title")).font(.system(size: 19, weight: .semibold))
                    Text(m.text(reader.errorKey ?? (path == nil ? "missing_report" : "empty_report")))
                        .font(.system(size: 13)).foregroundStyle(DesignTokens.muted)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button(m.text("choose_markdown")) { store.chooseFile(history: store.historyTab) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }.frame(maxWidth: 300).padding(DesignTokens.content * 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
