import AppKit
import NotchControlCore
import SwiftUI
import XCTest
@testable import NotchControl
@testable import NotchControlUI

final class MarkdownReaderTests: XCTestCase {
    private let markdown = """
    # Notas do projeto

    Uma leitura com **destaque**, *ênfase*, ~~riscado~~ e `código inline`.

    ## Próximos passos
    - [x] Leitor nativo
    - [ ] Conferir o documento
      - Uma lista aninhada

    1. Abrir arquivo
    2. Ler e copiar

    > O arquivo permanece intacto. Mudanças externas aparecem automaticamente.

    ```swift
    let message = "Olá, mundo"
    print(message)
    ```

    | Recurso | Estado |
    | --- | --- |
    | Markdown | Pronto |
    | Edição | Desativada |

    [Documentação ↗](https://example.com)
    """

    @MainActor
    func testMarkdownPreservesStructureStylesAndOnlyExternalLinks() throws {
        let value = MarkdownRenderer.render(markdown + "\n\n[unsafe](file:///tmp/sample)\n\n[shell](javascript:alert)")
        let text = value.string as NSString
        func attributes(_ word: String) throws -> [NSAttributedString.Key: Any] {
            let range = text.range(of: word)
            XCTAssertNotEqual(range.location, NSNotFound)
            return value.attributes(at: range.location, effectiveRange: nil)
        }
        XCTAssertTrue(value.string.contains("☑\tLeitor nativo"))
        XCTAssertTrue(value.string.contains("☐\tConferir"))
        XCTAssertTrue(value.string.contains("1.\tAbrir"))
        XCTAssertTrue(value.string.contains("2.\tLer"))
        let heading = try XCTUnwrap(try attributes("Notas")[.font] as? NSFont)
        let body = try XCTUnwrap(try attributes("Uma leitura")[.font] as? NSFont)
        XCTAssertGreaterThan(heading.pointSize, body.pointSize)
        let list = try XCTUnwrap(try attributes("Uma lista")[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertGreaterThan(list.headIndent, 20)
        let code = try XCTUnwrap(try attributes("let message")[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertNotNil(code.textBlocks.first?.backgroundColor)
        let cell = try XCTUnwrap((try attributes("Pronto")[.paragraphStyle] as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock)
        XCTAssertEqual(cell.table.numberOfColumns, 2)
        XCTAssertEqual(cell.startingRow, 1)
        XCTAssertEqual(cell.startingColumn, 1)
        XCTAssertNotNil(try attributes("Documentação")[.link])
        XCTAssertNil(try attributes("unsafe")[.link])
        XCTAssertNil(try attributes("shell")[.link])
        XCTAssertNotNil(try attributes("riscado")[.strikethroughStyle])
    }

    @MainActor
    func testNativeReaderIsReadOnlyAndPreservesScrollOnRefresh() async throws {
        let longText = (0..<60).map { "## Seção \($0)\n\nTexto de leitura com **formatação**." }.joined(separator: "\n\n")
        let host = NSHostingView(rootView: MarkdownReader(markdown: longText, documentID: "work", accessibilityLabel: "Documento"))
        let window = makeWindow(host, width: 360)
        defer { window.close() }
        try await settle(host)
        let text = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        let scroll = try XCTUnwrap(text.enclosingScrollView)
        XCTAssertFalse(text.isEditable)
        XCTAssertTrue(text.isSelectable)
        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertGreaterThan(text.frame.height, scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)
        text.setSelectedRange(NSRange(location: 10, length: 5))
        let origin = scroll.contentView.bounds.origin
        host.rootView = MarkdownReader(markdown: longText + "\n\nAtualização", documentID: "work", accessibilityLabel: "Documento")
        try await settle(host)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, origin.y, accuracy: 1)
        XCTAssertEqual(text.selectedRange(), NSRange(location: 10, length: 5))
        host.rootView = MarkdownReader(markdown: "# Histórico", documentID: "history", accessibilityLabel: "Documento")
        try await settle(host)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0, accuracy: 1)
        XCTAssertEqual(text.selectedRange().length, 0)
    }

    @MainActor
    func testReportPanelLoadsLocalMarkdownAndRendersEmptyAndNarrowStates() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notas.md")
        try markdown.write(to: file, atomically: true, encoding: .utf8)
        let store = AppStore(project: folder)
        defer { store.work.stop(); store.history.stop() }
        store.content = "report"
        store.preferences.language = .portuguese
        XCTAssertEqual(store.messages.text("choose_markdown"), "Abrir Markdown")
        XCTAssertEqual(Messages(language: .english).text("choose_markdown"), "Open Markdown")
        let host = NSHostingView(rootView: PanelContent(store: store).preferredColorScheme(.dark))
        let window = makeWindow(host, width: 560)
        defer { window.close() }
        try await settle(host)
        try snapshot(host, name: "report-empty")
        XCTAssertTrue(descendants(host).compactMap { $0 as? NSTextView }.isEmpty)
        store.preferences.workPath = file.path
        store.work.open(file.path)
        try await Task.sleep(for: .milliseconds(1200))
        try await settle(host)
        let reader = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        XCTAssertTrue(reader.string.contains("Notas do projeto"))
        XCTAssertFalse(reader.isEditable)
        let quote = (reader.string as NSString).range(of: "O arquivo permanece intacto.")
        let layout = try XCTUnwrap(reader.layoutManager)
        let container = try XCTUnwrap(reader.textContainer)
        let quoteBounds = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: quote, actualCharacterRange: nil), in: container)
        XCTAssertGreaterThan(quoteBounds.width, 100)
        XCTAssertLessThan(quoteBounds.height, 100)
        try snapshot(host, name: "report-markdown")
        window.setContentSize(NSSize(width: 360, height: 740))
        try await settle(host)
        XCTAssertLessThanOrEqual(reader.frame.width, 360)
        try snapshot(host, name: "report-narrow")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), markdown)
        let missing = folder.appendingPathComponent("missing.md").path
        store.preferences.historyPath = missing
        store.history.open(missing)
        store.historyTab = true
        try await settle(host)
        XCTAssertEqual(store.history.errorKey, "file_unavailable")
        XCTAssertTrue(descendants(host).compactMap { $0 as? NSTextView }.isEmpty)
        try snapshot(host, name: "report-error")
    }

    @MainActor
    private func makeWindow(_ host: NSView, width: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: width, height: 740),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        return window
    }

    @MainActor
    private func settle(_ host: NSView) async throws {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor
    private func snapshot(_ host: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["NC_MARKDOWN_PREVIEWS"] else { return }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}
