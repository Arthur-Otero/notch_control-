import XCTest
@testable import NotchControlCore

final class PanelGeometryTests: XCTestCase {
    func testPanelRespectsUsableMonitorAndRailOnEitherEdge() {
        let screen = ScreenArea(x: -1440, y: 40, width: 1440, height: 850)
        let left = PanelLayout(screen: screen, edge: .left, preferredWidth: 560, railWidth: 52)
        XCTAssertEqual(left.content, ScreenArea(x: -1440, y: 40, width: 560, height: 850))
        let right = PanelLayout(screen: screen, edge: .right, preferredWidth: 3000, railWidth: 52)
        XCTAssertEqual(right.content, ScreenArea(x: -1152, y: 40, width: 1152, height: 850))
        XCTAssertTrue(PanelLayout.shouldClose(draggedWidth: 20))
        XCTAssertFalse(PanelLayout.shouldClose(draggedWidth: 100))
        let tiny = PanelLayout(screen: .init(x: 0, y: 0, width: 300, height: 400), edge: .right, preferredWidth: 560, railWidth: 52)
        XCTAssertGreaterThanOrEqual(tiny.content.x, 0)
        XCTAssertLessThanOrEqual(tiny.content.width + 52, 300)
    }
}
