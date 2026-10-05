import Foundation
import XCTest
@testable import NotchControlCore

final class TerminalWireTests: XCTestCase {
    func testRunsExpandIntoOneCellPerColumnWithSharedStyle() throws {
        let json = """
        {"runs":[{"t":["$"," "]},{"s":{"fg":{"ansi":2},"b":1,"v":1},"t":["o","k",""]}],"hardEOL":true}
        """
        let line = try JSONDecoder().decode(TerminalLine.self, from: Data(json.utf8))
        XCTAssertEqual(line.cells.map(\.text), ["$", " ", "o", "k", ""])
        XCTAssertNil(line.cells[0].foreground)
        XCTAssertFalse(line.cells[0].bold)
        XCTAssertEqual(line.cells[2].foreground?.ansi, 2)
        XCTAssertTrue(line.cells[3].bold)
        XCTAssertTrue(line.cells[3].inverse)
        XCTAssertFalse(line.cells[3].italic)
        XCTAssertTrue(line.hardEOL)
    }

    func testLegacyPerCellLinesStillDecode() throws {
        let json = """
        {"cells":[{"text":"x","foreground":null,"background":null,"bold":false,"italic":false,"underline":true,"inverse":false}],"hardEOL":false}
        """
        let line = try JSONDecoder().decode(TerminalLine.self, from: Data(json.utf8))
        XCTAssertEqual(line.cells.count, 1)
        XCTAssertTrue(line.cells[0].underline)
    }

    func testResumeCommandForCursorAgentIsRecognised() throws {
        let uuid = "00000000-0000-0000-0000-0000000000AB"
        let document = ReportDocument(markdown: "`cd /Users/me/project && agent --resume \(uuid)`")
        XCTAssertEqual(document.commands.first?.resume?.provider, .cursor)
        XCTAssertEqual(document.commands.first?.resume?.conversation, uuid.lowercased())
    }
}
