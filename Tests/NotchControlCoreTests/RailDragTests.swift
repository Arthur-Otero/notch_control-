import XCTest
@testable import NotchControlCore

final class RailDragTests: XCTestCase {
    func testGripMovementKeepsGrabOffsetInsteadOfJumpingToPointer() {
        let area = ScreenArea(x: 0, y: 40, width: 1440, height: 850)
        let drag = RailDrag(pointer: .init(x: 1410, y: 585), centerY: 465)
        let first = drag.placement(pointer: .init(x: 1410, y: 585), screenID: 1, area: area, height: 300)
        XCTAssertEqual(first.position, 0.5, accuracy: 0.001)
        let moved = drag.placement(pointer: .init(x: 1410, y: 605), screenID: 1, area: area, height: 300)
        XCTAssertEqual(area.y + moved.position * area.height, 485, accuracy: 0.001)
        XCTAssertEqual(moved.edge, .right)
    }
    func testDragCrossesToNegativeMonitorAndStaysAboveDock() {
        let drag = RailDrag(pointer: .init(x: 1410, y: 585), centerY: 465)
        let area = ScreenArea(x: -1440, y: 80, width: 1440, height: 820)
        let moved = drag.placement(pointer: .init(x: -1400, y: -400), screenID: 2, area: area, height: 300)
        XCTAssertEqual(moved.screenID, 2)
        XCTAssertEqual(moved.edge, .left)
        XCTAssertEqual(area.y + moved.position * area.height, 230, accuracy: 0.001)
        let frame = RailGeometry.frame(area: area, edge: moved.edge, position: moved.position, width: 70, height: 300)
        XCTAssertEqual(frame.x, -1440)
        XCTAssertEqual(frame.y, 80)
    }
    func testClickAndDragStayDistinctAndReleaseOutsideGripEndsOnce() {
        var gesture = RailPointerGesture()
        let press = RailPoint(x: 1410, y: 585)
        gesture.press(press)
        XCTAssertEqual(gesture.move(.init(x: 1411, y: 585)), [])
        XCTAssertEqual(gesture.release(press), [.clicked])
        gesture.press(press)
        let outside = RailPoint(x: 1100, y: 900)
        XCTAssertEqual(gesture.move(outside), [.began(press), .moved(outside)])
        XCTAssertEqual(gesture.release(outside).last, .ended(outside))
        XCTAssertEqual(gesture.release(outside), [])
        XCTAssertEqual(gesture.move(outside), [])
    }
    func testRailFrameClampsAtBothEndsWithoutChangingPointerAnchor() {
        let area = ScreenArea(x: 20, y: 40, width: 1000, height: 700)
        let top = RailGeometry.frame(area: area, edge: .right, position: 1, width: 70, height: 300)
        let bottom = RailGeometry.frame(area: area, edge: .left, position: 0, width: 70, height: 300)
        XCTAssertEqual(top, ScreenArea(x: 950, y: 440, width: 70, height: 300))
        XCTAssertEqual(bottom, ScreenArea(x: 20, y: 40, width: 70, height: 300))
        let drag = RailDrag(pointer: .init(x: 30, y: 730), centerY: top.y + top.height / 2)
        let moved = drag.placement(pointer: .init(x: 30, y: 710), screenID: 3, area: area, height: 300)
        XCTAssertEqual(area.y + area.height * moved.position, 570, accuracy: 0.001)
    }
}
