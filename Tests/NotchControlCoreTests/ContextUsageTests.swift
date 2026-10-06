import XCTest
@testable import NotchControlCore

final class ContextUsageTests: XCTestCase {
    func testContextLevelsChangeAtThirtyAndSeventyAndAccountLevelsAtFiftyAndEighty() {
        XCTAssertEqual([0, 29.9, 30, 69.9, 70, 100].map(UsageLevel.context), [.low, .low, .medium, .medium, .high, .high])
        XCTAssertEqual([0, 49.9, 50, 79.9, 80, 100].map(UsageLevel.account), [.low, .low, .medium, .medium, .high, .high])
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
