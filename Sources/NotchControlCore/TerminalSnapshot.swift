import Foundation

public struct TerminalCursor: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct TerminalColor: Decodable, Equatable, Sendable {
    public let rgb: [Int]?
    public let ansi: Int?
    public let alternate: Int?
}

public struct TerminalCell: Decodable, Equatable, Sendable {
    public let text: String
    public let foreground: TerminalColor?
    public let background: TerminalColor?
    public let bold: Bool
    public let italic: Bool
    public let underline: Bool
    public let inverse: Bool

    public init(text: String, foreground: TerminalColor? = nil, background: TerminalColor? = nil,
                bold: Bool = false, italic: Bool = false, underline: Bool = false, inverse: Bool = false) {
        self.text = text; self.foreground = foreground; self.background = background
        self.bold = bold; self.italic = italic; self.underline = underline; self.inverse = inverse
    }
}

/// Linha da grade. O fio carrega trechos de estilo único (`runs`) em vez de um objeto por célula: a tela
/// de um terminal comum cai de centenas de KB para poucos KB. O formato por célula (`cells`) segue aceito.
public struct TerminalLine: Decodable, Equatable, Sendable {
    public let cells: [TerminalCell]
    public let hardEOL: Bool

    public init(cells: [TerminalCell], hardEOL: Bool) {
        self.cells = cells; self.hardEOL = hardEOL
    }

    private struct Style: Decodable {
        let fg: TerminalColor?
        let bg: TerminalColor?
        let b: Int?
        let i: Int?
        let u: Int?
        let v: Int?
    }
    private struct Run: Decodable {
        let s: Style?
        let t: [String]
    }
    private enum Keys: String, CodingKey { case cells, runs, hardEOL }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        hardEOL = try container.decode(Bool.self, forKey: .hardEOL)
        if let runs = try container.decodeIfPresent([Run].self, forKey: .runs) {
            cells = runs.flatMap { run in
                run.t.map { text in
                    TerminalCell(text: text, foreground: run.s?.fg, background: run.s?.bg,
                                 bold: run.s?.b == 1, italic: run.s?.i == 1, underline: run.s?.u == 1, inverse: run.s?.v == 1)
                }
            }
        } else {
            cells = try container.decode([TerminalCell].self, forKey: .cells)
        }
    }
}

public struct TerminalPalette: Decodable, Equatable, Sendable {
    public let foreground: [Int]
    public let background: [Int]
    public let ansi: [[Int]]
}

public struct TerminalSnapshot: Decodable, Equatable, Sendable {
    public let connection: String
    public let terminal: TerminalIdentity
    public let selection: UInt64
    public let columns: Int
    public let rows: Int
    public let cursor: TerminalCursor
    public let lines: [TerminalLine]
    public let palette: TerminalPalette?

    public init(connection: String, terminal: TerminalIdentity, selection: UInt64,
                columns: Int, rows: Int, cursor: TerminalCursor, lines: [TerminalLine], palette: TerminalPalette? = nil) {
        self.connection = connection
        self.terminal = terminal
        self.selection = selection
        self.columns = columns
        self.rows = rows
        self.cursor = cursor
        self.lines = lines
        self.palette = palette
    }
}
