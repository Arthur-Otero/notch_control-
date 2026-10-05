import XCTest
@testable import NotchControlCore

final class AlertTests: XCTestCase {
    func testBaselineAndRepeatedWaitAreSilentButNewCycleAlerts() {
        var alerts = AlertTracker()
        XCTAssertNil(alerts.observe(id: "a", state: .waiting, sequence: 1, kind: .waiting, baseline: true))
        XCTAssertNil(alerts.observe(id: "a", state: .waiting, sequence: 2, kind: .waiting))
        XCTAssertNil(alerts.observe(id: "a", state: .working, sequence: 3, kind: .working))
        XCTAssertEqual(alerts.observe(id: "a", state: .waiting, sequence: 4, kind: .waiting), .waiting)
        XCTAssertNil(alerts.observe(id: "a", state: .idle, sequence: 5, kind: .interrupted))
        XCTAssertNil(alerts.observe(id: "a", state: .working, sequence: 6, kind: .working))
        XCTAssertEqual(alerts.observe(id: "a", state: .idle, sequence: 7, kind: .completed), .completed)
        XCTAssertNil(alerts.observe(id: "a", state: .idle, sequence: 7, kind: .completed))
    }
}
