import AppKit
import NotchControlCore
import SwiftUI

public struct TerminalMirror: NSViewRepresentable {
    let snapshot: TerminalSnapshot?
    let enabled: Bool
    let send: (String) -> Void
    let history: [TerminalLine]
    let historyRevision: UInt64
    let historyOnly: Bool
    let focusOnSelection: Bool
    let labels: [String: String]
    public init(snapshot: TerminalSnapshot?, enabled: Bool, send: @escaping (String) -> Void,
                history: [TerminalLine] = [], historyRevision: UInt64 = 0, historyOnly: Bool = false, focusOnSelection: Bool = false, labels: [String: String] = [:]) {
        self.snapshot = snapshot; self.enabled = enabled; self.send = send
        self.history = history; self.historyRevision = historyRevision; self.historyOnly = historyOnly; self.focusOnSelection = focusOnSelection; self.labels = labels
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = TerminalScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.scrollerStyle = .legacy
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.appearance = NSAppearance(named: .darkAqua)
        scroll.documentView = TerminalCanvas(frame: .zero)
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let terminal = scroll.documentView as? TerminalCanvas else { return }
        let switched = terminal.snapshot?.terminal != snapshot?.terminal || terminal.snapshot?.selection != snapshot?.selection
        let pageChanged = terminal.historyOnly != historyOnly || (historyOnly && terminal.historyRevision != historyRevision)
        terminal.historyOnly = historyOnly; terminal.historyRevision = historyRevision
        let followEnd = switched || scroll.contentView.bounds.maxY >= terminal.bounds.height - 2
        let oldOrigin = scroll.contentView.bounds.origin
        if switched { terminal.clearSelection() }
        if let snapshot {
            let columns = max(snapshot.columns, history.map { $0.cells.count }.max() ?? snapshot.columns)
            terminal.snapshot = TerminalSnapshot(connection: snapshot.connection, terminal: snapshot.terminal, selection: snapshot.selection,
                                                  columns: columns, rows: historyOnly ? max(1, history.count) : snapshot.rows + history.count,
                                                  cursor: .init(x: historyOnly ? -1 : snapshot.cursor.x, y: snapshot.cursor.y + history.count), lines: historyOnly ? history : history + snapshot.lines, palette: snapshot.palette)
        } else { terminal.snapshot = nil }
        scroll.backgroundColor = terminal.paletteBackground
        terminal.labels = labels
        terminal.setAccessibilityLabel(labels["terminal"] ?? "Interactive terminal")
        terminal.inputEnabled = enabled
        terminal.send = send
        terminal.setFrameSize(NSSize(width: max(scroll.contentSize.width, CGFloat(terminal.snapshot?.columns ?? 80) * TerminalCanvas.cellWidth + 16),
                                     height: max(scroll.contentSize.height, CGFloat(terminal.snapshot?.rows ?? 24) * TerminalCanvas.cellHeight + 16)))
        if pageChanged, historyOnly { terminal.clearSelection(); scroll.contentView.scroll(to: .zero) }
        else if followEnd || (pageChanged && !historyOnly) { scroll.contentView.scroll(to: NSPoint(x: oldOrigin.x, y: max(0, terminal.bounds.height - scroll.contentSize.height))) }
        else { scroll.contentView.scroll(to: oldOrigin) }
        scroll.reflectScrolledClipView(scroll.contentView)
        if switched, enabled, focusOnSelection, !historyOnly { terminal.requestTypingFocus() }
        terminal.needsDisplay = true
    }
}

@MainActor
public final class TerminalCanvas: NSView, @MainActor NSTextInputClient {
    public static let font = NSFont.monospacedSystemFont(ofSize: DesignTokens.fontSize, weight: .regular)
    public static let cellWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
    public static let cellHeight: CGFloat = DesignTokens.cellHeight
    var snapshot: TerminalSnapshot?
    var historyOnly = false
    var historyRevision: UInt64 = 0
    var inputEnabled = false
    /// Fica pendente até a janela ser a key window: abrir pelo notch acontece antes disso, e o foco não pode se perder nesse intervalo.
    private(set) var waitingToType = false
    private var keyObserver: NSObjectProtocol?
    var send: ((String) -> Void)?
    var labels: [String: String] = [:]
    private var anchor: Int?
    private var extent: Int?
    private var selectionSnapshot: TerminalSnapshot?
    private var marked = NSAttributedString(string: "")
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityLabel("Espelho interativo do terminal selecionado")
        setAccessibilityRole(.textArea)
    }

    public required init?(coder: NSCoder) { nil }

    public func clearSelection() {
        anchor = nil
        selectionSnapshot = nil
        extent = nil
        marked = NSAttributedString(string: "")
    }

    private var selectedCells: ClosedRange<Int>? {
        guard let anchor, let extent else { return nil }
        return min(anchor, extent)...max(anchor, extent)
    }

    /// Pede o foco uma vez por seleção. Teclas como `/` precisam chegar ao CLI para ele desenhar as próprias sugestões.
    func requestTypingFocus() {
        waitingToType = true
        deliverTypingFocus()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        guard let window else { return }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliverTypingFocus() }
        }
        deliverTypingFocus()
    }

    private func deliverTypingFocus() {
        guard waitingToType, inputEnabled, let window, window.isKeyWindow else { return }
        waitingToType = false
        if window.firstResponder !== self { window.makeFirstResponder(self) }
    }

    public override func draw(_ dirtyRect: NSRect) {
        defaultBackground.setFill()
        dirtyRect.fill()
        guard let snapshot else {
            ((labels["empty"] ?? "Select a terminal.") as NSString)
                .draw(at: NSPoint(x: 16, y: 16), withAttributes: [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor])
            return
        }
        let firstRow = max(0, Int((dirtyRect.minY - 8) / Self.cellHeight))
        let lastRow = min(snapshot.lines.count, Int(dirtyRect.maxY / Self.cellHeight) + 1)
        guard firstRow < lastRow else { return }
        for row in firstRow..<lastRow {
            for (column, cell) in snapshot.lines[row].cells.enumerated() {
                let rect = cellRect(column: column, row: row)
                guard rect.intersects(dirtyRect) else { continue }
                let foreground = color(cell.foreground, fallback: defaultForeground, reverse: defaultBackground)
                let background = color(cell.background, fallback: defaultBackground, reverse: defaultForeground)
                (cell.inverse ? foreground : background).setFill()
                rect.fill()
                if selectedCells?.contains(row * snapshot.columns + column) == true {
                    NSColor.selectedTextBackgroundColor.withAlphaComponent(0.65).setFill()
                    rect.fill()
                }
            }
            for (column, cell) in snapshot.lines[row].cells.enumerated() where !cell.text.isEmpty {
                let rect = cellRect(column: column, row: row)
                guard rect.intersects(dirtyRect) else { continue }
                var font = Self.font
                if cell.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if cell.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                let foreground = cell.inverse ? color(cell.background, fallback: defaultBackground, reverse: defaultForeground) :
                    color(cell.foreground, fallback: defaultForeground, reverse: defaultBackground)
                var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
                if cell.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                (cell.text as NSString).draw(at: rect.origin, withAttributes: attributes)
            }
        }
        if (0..<snapshot.columns).contains(snapshot.cursor.x), (0..<snapshot.rows).contains(snapshot.cursor.y) {
            let rect = cellRect(column: snapshot.cursor.x, row: snapshot.cursor.y)
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            if !marked.string.isEmpty {
                marked.draw(at: NSPoint(x: rect.minX, y: rect.maxY))
            }
        }
    }

    private func cellRect(column: Int, row: Int) -> NSRect {
        NSRect(x: 8 + CGFloat(column) * Self.cellWidth, y: 8 + CGFloat(row) * Self.cellHeight,
               width: Self.cellWidth, height: Self.cellHeight)
    }

    /// Fundo do perfil do iTerm2; o scroll view o usa para não deixar faixas de outra cor ao redor da grade.
    var paletteBackground: NSColor { defaultBackground }
    private var defaultForeground: NSColor { rgb(snapshot?.palette?.foreground) ?? .textColor }
    private var defaultBackground: NSColor { rgb(snapshot?.palette?.background) ?? .textBackgroundColor }
    private func rgb(_ value: [Int]?) -> NSColor? {
        guard let value, value.count == 3, value.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return NSColor(srgbRed: CGFloat(value[0]) / 255, green: CGFloat(value[1]) / 255, blue: CGFloat(value[2]) / 255, alpha: 1)
    }
    private func color(_ value: TerminalColor?, fallback: NSColor, reverse: NSColor) -> NSColor {
        if let rgb = value?.rgb, rgb.count == 3, rgb.allSatisfy({ (0...255).contains($0) }) {
            return NSColor(srgbRed: CGFloat(rgb[0]) / 255, green: CGFloat(rgb[1]) / 255, blue: CGFloat(rgb[2]) / 255, alpha: 1)
        }
        guard let ansi = value?.ansi, (0...255).contains(ansi) else {
            return value?.alternate == 1 ? reverse : fallback
        }
        let palette: [NSColor] = [.black, .systemRed, .systemGreen, .systemYellow, .systemBlue, .systemPurple, .systemTeal, .lightGray,
                                  .darkGray, .systemRed, .systemGreen, .systemYellow, .systemBlue, .systemPurple, .systemCyan, .white]
        if ansi < 16 {
            if let colors = snapshot?.palette?.ansi, colors.indices.contains(ansi), let color = rgb(colors[ansi]) { return color }
            return palette[ansi]
        }
        if ansi >= 232 {
            return NSColor(white: CGFloat(8 + (ansi - 232) * 10) / 255, alpha: 1)
        }
        let index = ansi - 16
        let levels: [CGFloat] = [0, 95, 135, 175, 215, 255]
        return NSColor(srgbRed: levels[index / 36] / 255, green: levels[(index / 6) % 6] / 255,
                       blue: levels[index % 6] / 255, alpha: 1)
    }

    private func cellIndex(_ event: NSEvent) -> Int? {
        guard let snapshot else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let column = min(snapshot.columns - 1, max(0, Int((point.x - 8) / Self.cellWidth)))
        let row = min(snapshot.rows - 1, max(0, Int((point.y - 8) / Self.cellHeight)))
        return row * snapshot.columns + column
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selectionSnapshot = snapshot
        anchor = cellIndex(event)
        extent = anchor
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        extent = cellIndex(event)
        autoscroll(with: event)
        needsDisplay = true
    }

    @objc func copy(_ sender: Any?) {
        guard let snapshot = selectionSnapshot ?? snapshot, let selection = selectedCells else { return }
        var text = ""
        for row in 0..<snapshot.lines.count {
            let line = snapshot.lines[row]
            var fragment = ""
            for (column, cell) in line.cells.enumerated() where selection.contains(row * snapshot.columns + column) {
                fragment += cell.text
            }
            if selection.overlaps((row * snapshot.columns)...max(row * snapshot.columns, (row + 1) * snapshot.columns - 1)) {
                while fragment.last == " " { fragment.removeLast() }
                text += fragment
                if line.hardEOL && selection.upperBound >= (row + 1) * snapshot.columns { text += "\n" }
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard inputEnabled, let text = NSPasteboard.general.string(forType: .string) else { return }
        if text.contains("\n") || text.contains("\r") {
            let alert = NSAlert()
            alert.messageText = labels["paste_title"] ?? "Paste multiple lines?"
            alert.informativeText = labels["paste_message"] ?? "Line breaks may submit commands."
            alert.addButton(withTitle: labels["paste"] ?? "Paste")
            alert.addButton(withTitle: labels["cancel"] ?? "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        send?(text)
    }

    public override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { super.keyDown(with: event); return }
        guard inputEnabled else { NSSound.beep(); return }
        if hasMarkedText() { interpretKeyEvents([event]); return }
        let sequences: [UInt16: String] = [123: "\u{1b}[D", 124: "\u{1b}[C", 125: "\u{1b}[B", 126: "\u{1b}[A",
                                            53: "\u{1b}", 48: "\t", 36: "\r", 76: "\r", 51: "\u{7f}", 117: "\u{1b}[3~",
                                            115: "\u{1b}[H", 119: "\u{1b}[F", 116: "\u{1b}[5~", 121: "\u{1b}[6~"]
        if let sequence = sequences[event.keyCode] {
            if event.keyCode == 48, event.modifierFlags.contains(.shift) { send?("\u{1b}[Z") }
            else { send?(sequence) }
            return
        }
        if event.modifierFlags.contains(.control), let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
           scalar.value < 128, let control = UnicodeScalar(scalar.value & 0x1f) {
            send?(String(control))
            return
        }
        interpretKeyEvents([event])
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        marked = NSAttributedString(string: "")
        if inputEnabled { send?(text) }
        needsDisplay = true
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = (string as? NSAttributedString) ?? NSAttributedString(string: string as? String ?? "")
        needsDisplay = true
    }

    public func unmarkText() { marked = NSAttributedString(string: ""); needsDisplay = true }
    public func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    public func markedRange() -> NSRange { NSRange(location: marked.length == 0 ? NSNotFound : 0, length: marked.length) }
    public func hasMarkedText() -> Bool { marked.length > 0 }
    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let intersection = NSIntersectionRange(range, NSRange(location: 0, length: marked.length))
        actualRange?.pointee = intersection
        return intersection.length > 0 ? marked.attributedSubstring(from: intersection) : nil
    }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [.font, .foregroundColor, .underlineStyle] }
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        let rect = cellRect(column: snapshot?.cursor.x ?? 0, row: snapshot?.cursor.y ?? 0)
        return window?.convertToScreen(convert(rect, to: nil)) ?? rect
    }
    public func characterIndex(for point: NSPoint) -> Int { 0 }
    public override func doCommand(by selector: Selector) {
        guard inputEnabled else { return }
        switch NSStringFromSelector(selector) {
        case "insertNewline:": send?("\r")
        case "insertTab:": send?("\t")
        case "deleteBackward:": send?("\u{7f}")
        case "cancelOperation:": send?("\u{1b}")
        default: break
        }
    }
}

public enum PanelMetrics {
    public static let headerHeight: CGFloat = 56
    public static let outputInset: CGFloat = 10
    /// Largura fora da grade: alça, margens do cartão, respiro e scroller.
    public static let terminalChromeWidth: CGFloat = 56
    /// Altura fora da grade: cabeçalho, margens do cartão, respiro e scroller. A entrada é a do próprio terminal.
    public static var terminalChromeHeight: CGFloat { headerHeight + 1 + outputInset * 2 + 16 }
}

public extension Notification.Name {
    static let notchControlJumpToEnd = Notification.Name("NotchControl.jumpToEnd")
}

@MainActor
private final class TerminalScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(self, selector: #selector(jumpToEnd), name: .notchControlJumpToEnd, object: nil)
    }
    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func jumpToEnd() {
        guard let documentView, window?.isVisible == true else { return }
        contentView.scroll(to: NSPoint(x: contentView.bounds.minX, y: max(0, documentView.bounds.height - contentSize.height)))
        reflectScrolledClipView(contentView)
    }
}
