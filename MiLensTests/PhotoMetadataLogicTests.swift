//  PhotoMetadataLogicTests —— 照片元数据构造决策纯逻辑测试
//  （对应源端 viewmodels/PhotoMetadataViewModel.ets）。
//  覆盖：EXIF 日期多格式解析 / 引号与空白剥离 / ISO8601 降级 / 兜底拍摄时间三级回退。

import XCTest
@testable import MiLens

final class PhotoMetadataLogicTests: XCTestCase {

    /// 与实现同构的日历（未设 timeZone 即系统本地），
    /// 期望值构造与被测解析用同一时区基准，测试与 runner 时区无关。
    private let localCal = Calendar(identifier: .gregorian)
    private let utcCal = PetDateCalendar.gregorian

    private func expectYMDH(_ date: Date, cal: Calendar,
                            year: Int, month: Int, day: Int, hour: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: date)
        XCTAssertEqual(comps.year, year, file: file, line: line)
        XCTAssertEqual(comps.month, month, file: file, line: line)
        XCTAssertEqual(comps.day, day, file: file, line: line)
        XCTAssertEqual(comps.hour, hour, file: file, line: line)
    }

    // MARK: - parseExifDateString

    /// EXIF 标准冒号格式解析。
    func testParseExifColonFormat() {
        let date = PhotoMetadataLogic.parseExifDateString("2026:01:15 10:30:00")
        XCTAssertNotNil(date)
        expectYMDH(date!, cal: localCal, year: 2026, month: 1, day: 15, hour: 10)
    }

    /// 横线分隔格式解析（部分来源导出该格式）。
    func testParseExifDashFormat() {
        let date = PhotoMetadataLogic.parseExifDateString("2025-12-31 23:59:59")
        XCTAssertNotNil(date)
        expectYMDH(date!, cal: localCal, year: 2025, month: 12, day: 31, hour: 23)
    }

    /// 首尾引号剥离（部分 EXIF 工具写入带引号的字符串）。
    func testParseStripsSurroundingQuotes() {
        let quoted = PhotoMetadataLogic.parseExifDateString(String("\u{22}2026:01:15 10:30:00\u{22}"))
        XCTAssertNotNil(quoted)
        expectYMDH(quoted!, cal: localCal, year: 2026, month: 1, day: 15, hour: 10)

        let single = PhotoMetadataLogic.parseExifDateString(String("\u{27}2026:01:15 10:30:00\u{27}"))
        XCTAssertNotNil(single)
    }

    /// 首尾空白与换行剥离。
    func testParseTrimsWhitespace() {
        let date = PhotoMetadataLogic.parseExifDateString("  2026:06:01 08:00:00 \n ")
        XCTAssertNotNil(date)
        expectYMDH(date!, cal: localCal, year: 2026, month: 6, day: 1, hour: 8)
    }

    /// ISO8601 降级解析（带 Z 后缀）。
    func testParseISO8601Fallback() {
        let date = PhotoMetadataLogic.parseExifDateString("2026-01-15T10:30:00Z")
        XCTAssertNotNil(date)
        expectYMDH(date!, cal: utcCal, year: 2026, month: 1, day: 15, hour: 10)
    }

    /// ISO8601 带毫秒降级解析。
    func testParseISO8601WithFractionalSeconds() {
        let date = PhotoMetadataLogic.parseExifDateString("2026-01-15T10:30:00.123Z")
        XCTAssertNotNil(date)
        expectYMDH(date!, cal: utcCal, year: 2026, month: 1, day: 15, hour: 10)
    }

    /// 完全无法解析的输入返回 nil。
    func testParseReturnsNilForGarbage() {
        XCTAssertNil(PhotoMetadataLogic.parseExifDateString("not a date"))
        XCTAssertNil(PhotoMetadataLogic.parseExifDateString(""))
        XCTAssertNil(PhotoMetadataLogic.parseExifDateString("   "))
    }

    /// 日/月/年格式不在支持范围（不误解析为错误日期）。
    func testParseReturnsNilForDayFirstFormat() {
        XCTAssertNil(PhotoMetadataLogic.parseExifDateString("15/01/2026"))
    }

    // MARK: - resolveFallbackTakenAt

    /// 已有 EXIF 日期直接返回（最高优先级）。
    func testFallbackPrefersExistingTakenAt() {
        let existing = Date(timeIntervalSince1970: 1_000_000)
        let result = PhotoMetadataLogic.resolveFallbackTakenAt(
            existingTakenAt: existing, statMtime: 2_000_000)
        XCTAssertEqual(result, existing)
    }

    /// 无 EXIF 时用文件修改时间（秒级时间戳）。
    func testFallbackUsesFileMtime() {
        let result = PhotoMetadataLogic.resolveFallbackTakenAt(
            existingTakenAt: nil, statMtime: 1_760_000_000)
        XCTAssertEqual(result.timeIntervalSince1970, 1_760_000_000, accuracy: 0.001)
    }

    /// 既无 EXIF 也无有效 mtime（0）时回退当前时间。
    func testFallbackFallsBackToNow() {
        let before = Date()
        let result = PhotoMetadataLogic.resolveFallbackTakenAt(
            existingTakenAt: nil, statMtime: 0)
        let after = Date()
        XCTAssertGreaterThanOrEqual(result, before.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(result, after.addingTimeInterval(1))
    }
}