import XCTest
@testable import NotchControlCore

final class ContextUsageTests: XCTestCase {
    func testLevelsChangeAtThirtyAndSeventyPercent() {
        XCTAssertEqual([0, 29.9, 30, 69.9, 70, 100].map { ContextLevel(usedPercent: $0) }, [.low, .low, .medium, .medium, .high, .high])
    }

    func testReadingsOutsideZeroToHundredAreRejectedAndAnExpiredOneIsValid() throws {
        func reading(_ value: String) throws -> ContextUsageReading {
            try JSONDecoder().decode(ContextUsageReading.self, from: Data(#"{"connection":"c","terminal":{"id":"t","generation":"1"},"usedPercent":\#(value)}"#.utf8))
        }
        XCTAssertTrue(try reading("12.5").isValid)
        XCTAssertTrue(try reading("null").isValid)
        XCTAssertFalse(try reading("120").isValid)
        XCTAssertFalse(try reading("-1").isValid)
    }
}
