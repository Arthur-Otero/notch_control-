import AppKit
import SwiftUI

public struct MarkdownReader: NSViewRepresentable {
    public let markdown: String
    public let documentID: String
    public let accessibilityLabel: String

    public init(markdown: String, documentID: String, accessibilityLabel: String) {
        self.markdown = markdown
        self.documentID = documentID
        self.accessibilityLabel = accessibilityLabel
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        let text = NSTextView(frame: .zero)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.importsGraphics = false
        text.drawsBackground = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: DesignTokens.content, height: DesignTokens.content)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.linkTextAttributes = [.foregroundColor: NSColor(DesignTokens.primary), .underlineStyle: NSUnderlineStyle.single.rawValue]
        text.delegate = context.coordinator
        scroll.documentView = text
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        text.setAccessibilityLabel(accessibilityLabel)
        guard context.coordinator.markdown != markdown || context.coordinator.documentID != documentID else { return }
        let sameDocument = context.coordinator.documentID == documentID
        let origin = scroll.contentView.bounds.origin
        let selection = text.selectedRange()
        context.coordinator.markdown = markdown
        context.coordinator.documentID = documentID
        text.textStorage?.setAttributedString(MarkdownRenderer.render(markdown))
        if let container = text.textContainer { text.layoutManager?.ensureLayout(for: container) }
        if sameDocument, NSMaxRange(selection) <= text.string.utf16.count { text.setSelectedRange(selection) }
        else { text.setSelectedRange(NSRange(location: 0, length: 0)) }
        scroll.contentView.scroll(to: sameDocument ? origin : .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var markdown: String?
        var documentID: String?

        public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL, MarkdownRenderer.isExternalLink(url) { NSWorkspace.shared.open(url) }
            return true
        }
    }
}

@MainActor
public enum MarkdownRenderer {
    public static func isExternalLink(_ url: URL) -> Bool {
        ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }

    public static func render(_ markdown: String) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full))) ?? AttributedString(markdown)
        let output = NSMutableAttributedString(string: "")
        var previousBlock: Int?
        var paragraph = NSMutableParagraphStyle()
        var heading = 0
        var code = false
        var tableHeader = false
        var tables: [Int: NSTextTable] = [:]
        var previousAttributes: [NSAttributedString.Key: Any] = [:]
        var seenItems: Set<Int> = []

        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            let newBlock = output.length == 0 || block != previousBlock
            var text = String(parsed[run.range].characters)
            var prefix = ""
            if newBlock {
                if output.length > 0 { output.append(NSAttributedString(string: "\n", attributes: previousAttributes)) }
                previousBlock = block
                paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 4
                paragraph.paragraphSpacing = 12
                paragraph.lineBreakMode = .byWordWrapping
                heading = 0; code = false; tableHeader = false
                var listDepth = 0
                var item: (id: Int, ordinal: Int)?
                var ordered = false
                var foundList = false
                var quote = false
                var column: Int?
                var row = 0
                var table: NSTextTable?
                for component in components {
                    switch component.kind {
                    case .header(let level): heading = level
                    case .codeBlock: code = true
                    case .listItem(let ordinal):
                        listDepth += 1
                        if item == nil { item = (component.identity, ordinal) }
                    case .orderedList, .unorderedList:
                        if !foundList {
                            if case .orderedList = component.kind { ordered = true }
                            foundList = true
                        }
                    case .blockQuote: quote = true
                    case .tableCell(let index): column = index
                    case .tableHeaderRow: tableHeader = true
                    case .tableRow(let index): row = index
                    case .table(let columns):
                        if tables[component.identity] == nil {
                            let value = NSTextTable()
                            value.numberOfColumns = columns.count
                            value.layoutAlgorithm = .fixedLayoutAlgorithm
                            value.collapsesBorders = true
                            value.setContentWidth(100, type: .percentageValueType)
                            value.setWidth(10, type: .absoluteValueType, for: .margin, edge: .minY)
                            value.setWidth(10, type: .absoluteValueType, for: .margin, edge: .maxY)
                            tables[component.identity] = value
                        }
                        table = tables[component.identity]
                        if let column, columns.indices.contains(column) {
                            switch columns[column].alignment {
                            case .center: paragraph.alignment = .center
                            case .right: paragraph.alignment = .right
                            default: break
                            }
                        }
                    default: break
                    }
                }
                if let item {
                    paragraph.headIndent = CGFloat(listDepth) * 20
                    paragraph.firstLineHeadIndent = CGFloat(max(0, listDepth - 1)) * 20
                    paragraph.paragraphSpacing = 6
                    paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
                    if seenItems.insert(item.id).inserted {
                        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { prefix = "☑\t"; text = String(text.dropFirst(4)) }
                        else if text.hasPrefix("[ ] ") { prefix = "☐\t"; text = String(text.dropFirst(4)) }
                        else { prefix = ordered ? "\(item.ordinal).\t" : "•\t" }
                    } else { paragraph.firstLineHeadIndent = paragraph.headIndent }
                }
                if heading > 0 {
                    paragraph.paragraphSpacingBefore = output.length > 0 ? 12 : 0
                    paragraph.paragraphSpacing = 10
                    paragraph.headerLevel = heading
                }
                if code || quote {
                    let block = NSTextBlock()
                    block.setContentWidth(100, type: .percentageValueType)
                    block.setWidth(12, type: .absoluteValueType, for: .padding)
                    block.setWidth(10, type: .absoluteValueType, for: .margin, edge: .maxY)
                    if code {
                        block.backgroundColor = NSColor(DesignTokens.surface)
                        paragraph.paragraphSpacing = 0
                        paragraph.lineSpacing = 3
                    }
                    if quote {
                        block.setWidth(2, type: .absoluteValueType, for: .border, edge: .minX)
                        block.setBorderColor(NSColor(DesignTokens.border))
                    }
                    paragraph.textBlocks = [block]
                }
                if let table, let column {
                    let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                    cell.setContentWidth(100 / CGFloat(max(1, table.numberOfColumns)), type: .percentageValueType)
                    cell.setWidth(8, type: .absoluteValueType, for: .padding)
                    cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                    cell.setBorderColor(NSColor(DesignTokens.border))
                    if tableHeader { cell.backgroundColor = NSColor(DesignTokens.surface) }
                    paragraph.textBlocks = [cell]
                    paragraph.paragraphSpacing = 0
                }
            }
            let inline = run.inlinePresentationIntent ?? []
            if code, text.hasSuffix("\n") { text.removeLast() }
            let monospaced = code || inline.contains(.code)
            let size: CGFloat = heading > 0 ? [26, 21, 17, 15, 14, 13][min(heading, 6) - 1] : 13
            let weight: NSFont.Weight = heading > 0 || tableHeader || inline.contains(.stronglyEmphasized) ? .semibold : .regular
            var font = monospaced ? NSFont.monospacedSystemFont(ofSize: 12, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
            if inline.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor(DesignTokens.text), .paragraphStyle: paragraph
            ]
            if inline.contains(.code) { attributes[.backgroundColor] = NSColor(DesignTokens.surface) }
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link, isExternalLink(link) {
                attributes[.link] = link
                attributes[.toolTip] = link.absoluteString
            }
            output.append(NSAttributedString(string: prefix + text, attributes: attributes))
            previousAttributes = attributes
        }
        if output.length > 0 { output.append(NSAttributedString(string: "\n", attributes: previousAttributes)) }
        return output
    }
}
