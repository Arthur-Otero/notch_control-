import XCTest
@testable import NotchControlCore

final class ReportActionsTests: XCTestCase {
    func testReportOffersSafeResumeAndPreservesLiteralCopyForOtherCommands() {
        let safe = "cd '/Users/test/My Project' && codex resume 00000000-0000-0000-0000-000000000002"
        let unsafe = safe + "; touch /tmp/unwanted"
        let commands = ReportDocument(markdown: "# Work\n    \(safe)\n    \(unsafe)\n    cd /Users/test\n").commands
        XCTAssertEqual(commands.count, 3)
        XCTAssertEqual(commands[0].resume?.directory, "/Users/test/My Project")
        XCTAssertEqual(commands[0].resume?.provider, .codex)
        XCTAssertNil(commands[1].resume)
        XCTAssertEqual(commands[1].literal, unsafe)
        XCTAssertNil(commands[2].resume)
    }
    func testRenderedReportKeepsHeadingsAndListItemsOnSeparateLines() {
        let document = ReportDocument(markdown: "# Work\n\n## Task\n- Status: running\n- Sessions:\n  - first\n  - second")
        let text = String(document.readableMarkdown.characters)
        XCTAssertTrue(text.hasPrefix("Work\n"))
        XCTAssertTrue(text.contains("Task\n"))
        XCTAssertTrue(text.contains("• Status: running\n"))
        XCTAssertTrue(text.contains("• Sessions:\n  • first\n  • second"))
    }
}
