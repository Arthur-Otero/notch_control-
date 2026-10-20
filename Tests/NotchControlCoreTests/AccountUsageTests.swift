import Foundation
import XCTest
@testable import NotchControlCore

final class AccountUsageTests: XCTestCase {
    func testCacheExpiresAtTwoMinutesWithoutChangingTheReportedPercent() throws {
        let reading = try decode(#"{"loading":true,"updatedAt":1000,"errorCode":null}"#)
        XCTAssertTrue(reading.isValid)
        XCTAssertFalse(try XCTUnwrap(reading.refresh).isStale(at: Date(timeIntervalSince1970: 1119)))
        XCTAssertTrue(try XCTUnwrap(reading.refresh).isStale(at: Date(timeIntervalSince1970: 1120)))
        XCTAssertEqual(reading.windows.first?.usedPercent, 33)
    }

    func testRefreshMetadataRejectsUnknownErrorsAndUnrepresentableDates() throws {
        XCTAssertFalse(try decode(#"{"loading":false,"updatedAt":-1}"#).isValid)
        XCTAssertFalse(try decode(#"{"loading":false,"updatedAt":1e300}"#).isValid)
        XCTAssertFalse(try decode(#"{"loading":false,"errorCode":"private server response"}"#).isValid)
        XCTAssertTrue(try decode(#"{"loading":false,"errorCode":"codex_usage_rate_limited"}"#).isValid)
    }

    func testFooterReadingsStillDecodeWithoutRefreshMetadata() throws {
        let reading = try decode("null")
        XCTAssertTrue(reading.isValid)
        XCTAssertNil(reading.refresh)
    }

    private func decode(_ refresh: String) throws -> AccountUsageReading {
        let json = #"{"connection":"c","terminal":{"id":"t","generation":"one"},"windows":[{"id":"five_hour","usedPercent":33}],"refresh":\#(refresh)}"#
        return try JSONDecoder().decode(AccountUsageReading.self, from: Data(json.utf8))
    }
}
