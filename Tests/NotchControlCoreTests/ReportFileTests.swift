import Foundation
import XCTest
@testable import NotchControlCore

final class ReportFileTests: XCTestCase {
    func testExternalWritesAndAtomicReplacementUpdateWithoutWritingReport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("work.md")
        try "# Original".write(to: path, atomically: true, encoding: .utf8)
        var reader = ReportFileReader(path: path.path)
        reader.refresh()
        XCTAssertTrue(reader.isLoading)
        reader.refresh()
        XCTAssertEqual(reader.document.markdown, "# Original")
        XCTAssertFalse(reader.isLoading)
        XCTAssertNil(reader.errorKey)
        try "# Updated externally".write(to: path, atomically: false, encoding: .utf8)
        reader.refresh()
        XCTAssertEqual(reader.document.markdown, "# Original")
        XCTAssertTrue(reader.isLoading)
        reader.refresh()
        XCTAssertEqual(reader.document.markdown, "# Updated externally")
        try "# Replaced atomically".write(to: path, atomically: true, encoding: .utf8)
        let before = try FileManager.default.attributesOfItem(atPath: path.path)
        reader.refresh(); reader.refresh(); reader.refresh()
        let after = try FileManager.default.attributesOfItem(atPath: path.path)
        XCTAssertEqual(reader.document.markdown, "# Replaced atomically")
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), "# Replaced atomically")
    }

    func testMissingAndUnreadableContentKeepLastReadableDocumentAndRecover() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("work.md")
        var reader = ReportFileReader(path: path.path)
        reader.refresh()
        XCTAssertEqual(reader.errorKey, "file_unavailable")
        try "# Valid".write(to: path, atomically: true, encoding: .utf8)
        reader.refresh(); reader.refresh()
        try Data([0xff, 0xfe, 0xff]).write(to: path, options: .atomic)
        reader.refresh(); reader.refresh()
        XCTAssertEqual(reader.document.markdown, "# Valid")
        XCTAssertEqual(reader.errorKey, "read_failed")
        try FileManager.default.removeItem(at: path)
        reader.refresh()
        XCTAssertEqual(reader.document.markdown, "# Valid")
        try "# Recovered".write(to: path, atomically: true, encoding: .utf8)
        reader.refresh(); reader.refresh()
        XCTAssertEqual(reader.document.markdown, "# Recovered")
        XCTAssertNil(reader.errorKey)
    }
}
