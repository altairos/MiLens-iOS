import XCTest
@testable import MiLensKit

//  MemoryRecapLogic + ExportQuality 纯决策逻辑测试（ADR-0010 §3.3 / §10.12 / §10.13）。
//
//  无源端黄金规格（月度精选/年度回忆册为 iOS 自研情感触点），行为规格由本文件守护：
//  - 去重：跳过 duplicateOf != nil 的重复项
//  - 排序：qualityScore 降序 → isBest 优先 → takenAt 倒序
//  - 月度精选：按年月筛选 + 去重 + 排序 + 截取
//  - 年度回忆册：12 月汇总 + 年度代表
//  - ExportQuality：画质门控 + 尺寸缩放
//
//  全部日期用固定 UTC Calendar（miLensUTCCalendar）构造，任意时区可复现。

private enum RecapTestSupport {
    static func makeDate(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return miLensUTCCalendar.date(from: comps)!
    }

    static func makePhoto(
        id: UUID = UUID(),
        year: Int, month: Int, day: Int = 15,
        quality: Double = 0.5,
        isBest: Bool = false,
        duplicateOf: UUID? = nil
    ) -> RecapPhoto {
        RecapPhoto(
            id: id, takenAt: makeDate(year, month, day),
            qualityScore: quality, isBest: isBest, duplicateOf: duplicateOf
        )
    }
}

// MARK: - 去重

final class MemoryRecapDedupTests: XCTestCase {

    func testKeepsNonDuplicatePhotos() {
        let single = RecapTestSupport.makePhoto(year: 2025, month: 3)
        let best = RecapTestSupport.makePhoto(year: 2025, month: 3, isBest: true)
        let result = MemoryRecapLogic.deduplicate([single, best])
        XCTAssertEqual(result.count, 2)
    }

    func testFiltersOutDuplicateOfNonNil() {
        let bestID = UUID()
        let best = RecapTestSupport.makePhoto(id: bestID, year: 2025, month: 3, isBest: true)
        let dup = RecapTestSupport.makePhoto(year: 2025, month: 3, duplicateOf: bestID)
        let result = MemoryRecapLogic.deduplicate([best, dup])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, bestID)
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(MemoryRecapLogic.deduplicate([]).isEmpty)
    }
}

// MARK: - 排序

final class MemoryRecapSortTests: XCTestCase {

    func testSortsByQualityDescending() {
        let high = RecapTestSupport.makePhoto(year: 2025, month: 3, quality: 0.9)
        let mid = RecapTestSupport.makePhoto(year: 2025, month: 3, quality: 0.6)
        let low = RecapTestSupport.makePhoto(year: 2025, month: 3, quality: 0.3)
        let result = MemoryRecapLogic.sortedByQuality([mid, low, high])
        XCTAssertEqual(result.map(\.id), [high.id, mid.id, low.id])
    }

    func testUnscoredUsesFallback() {
        // qualityScore=0 视为 0.5（unscoredFallback）
        let unscored = RecapTestSupport.makePhoto(year: 2025, month: 3, quality: 0)
        let low = RecapTestSupport.makePhoto(year: 2025, month: 3, quality: 0.3)
        let result = MemoryRecapLogic.sortedByQuality([low, unscored])
        XCTAssertEqual(result.first?.id, unscored.id) // 0.5 > 0.3
    }

    func testIsBestBreaksTie() {
        let best = RecapTestSupport.makePhoto(year: 2025, month: 3, quality: 0.5, isBest: true)
        let normal = RecapTestSupport.makePhoto(year: 2025, month: 3, quality: 0.5)
        let result = MemoryRecapLogic.sortedByQuality([normal, best])
        XCTAssertEqual(result.first?.id, best.id)
    }

    func testTakenAtBreaksRemainingTie() {
        let older = RecapTestSupport.makePhoto(year: 2025, month: 3, day: 1, quality: 0.5)
        let newer = RecapTestSupport.makePhoto(year: 2025, month: 3, day: 28, quality: 0.5)
        let result = MemoryRecapLogic.sortedByQuality([older, newer])
        XCTAssertEqual(result.first?.id, newer.id)
    }
}

// MARK: - 月度精选

final class MonthlyRecapTests: XCTestCase {

    func testFiltersByYearMonth() {
        let inMonth = RecapTestSupport.makePhoto(id: UUID(), year: 2025, month: 3, quality: 0.8)
        let otherMonth = RecapTestSupport.makePhoto(id: UUID(), year: 2025, month: 4, quality: 0.9)
        let otherYear = RecapTestSupport.makePhoto(id: UUID(), year: 2024, month: 3, quality: 0.9)
        let recap = MemoryRecapLogic.monthlyRecap(
            photos: [inMonth, otherMonth, otherYear], year: 2025, month: 3)
        XCTAssertEqual(recap.photoIDs, [inMonth.id])
        XCTAssertEqual(recap.totalPhotoCount, 1)
    }

    func testRespectsLimit() {
        var photos: [RecapPhoto] = []
        for i in 0..<15 {
            photos.append(RecapTestSupport.makePhoto(
                id: UUID(), year: 2025, month: 3, quality: Double(15 - i) / 20.0))
        }
        let recap = MemoryRecapLogic.monthlyRecap(photos: photos, year: 2025, month: 3, limit: 5)
        XCTAssertEqual(recap.photoIDs.count, 5)
        XCTAssertEqual(recap.totalPhotoCount, 15)
    }

    func testDeduplicatesBeforeSelecting() {
        let bestID = UUID()
        let best = RecapTestSupport.makePhoto(
            id: bestID, year: 2025, month: 3, quality: 0.5, isBest: true)
        let dup = RecapTestSupport.makePhoto(
            year: 2025, month: 3, quality: 0.9, duplicateOf: bestID)
        let recap = MemoryRecapLogic.monthlyRecap(photos: [best, dup], year: 2025, month: 3)
        XCTAssertEqual(recap.photoIDs, [bestID])
        XCTAssertEqual(recap.totalPhotoCount, 2) // 去重前计数
    }

    func testEmptyMonth() {
        let recap = MemoryRecapLogic.monthlyRecap(photos: [], year: 2025, month: 3)
        XCTAssertTrue(recap.photoIDs.isEmpty)
        XCTAssertEqual(recap.totalPhotoCount, 0)
    }

    func testIgnoresPhotosWithoutTakenAt() {
        let noDate = RecapPhoto(id: UUID(), takenAt: nil, qualityScore: 0.9)
        let recap = MemoryRecapLogic.monthlyRecap(photos: [noDate], year: 2025, month: 3)
        XCTAssertTrue(recap.photoIDs.isEmpty)
    }

    func testMonthlyTitle() {
        XCTAssertEqual(MemoryRecapLogic.monthlyTitle(year: 2025, month: 3), "2025年3月")
        XCTAssertEqual(MemoryRecapLogic.monthlyTitle(year: 2025, month: 12), "2025年12月")
    }
}

// MARK: - 年度回忆册

final class YearlyRecapTests: XCTestCase {

    func testBuildsTwelveMonthsSkippingEmpty() {
        let mar = RecapTestSupport.makePhoto(id: UUID(), year: 2025, month: 3, quality: 0.8)
        let aug = RecapTestSupport.makePhoto(id: UUID(), year: 2025, month: 8, quality: 0.7)
        let recap = MemoryRecapLogic.yearlyRecap(photos: [mar, aug], year: 2025)
        XCTAssertEqual(recap.year, 2025)
        XCTAssertEqual(recap.months.count, 2) // 只有 3 月和 8 月有照片
        XCTAssertEqual(recap.months.first?.month, 3)
        XCTAssertEqual(recap.months.last?.month, 8)
        XCTAssertEqual(recap.totalPhotoCount, 2)
    }

    func testHeroPhotosCappedAtLimit() {
        var photos: [RecapPhoto] = []
        for m in 1...12 {
            for _ in 0..<3 {
                photos.append(RecapTestSupport.makePhoto(
                    id: UUID(), year: 2025, month: m, quality: Double(m) / 13.0))
            }
        }
        let recap = MemoryRecapLogic.yearlyRecap(photos: photos, year: 2025, heroLimit: 6)
        XCTAssertEqual(recap.heroPhotoIDs.count, 6)
        XCTAssertEqual(recap.months.count, 12)
    }

    func testYearlyExcludesOtherYears() {
        let y2024 = RecapTestSupport.makePhoto(id: UUID(), year: 2024, month: 3, quality: 0.99)
        let y2025 = RecapTestSupport.makePhoto(id: UUID(), year: 2025, month: 3, quality: 0.5)
        let recap = MemoryRecapLogic.yearlyRecap(photos: [y2024, y2025], year: 2025)
        XCTAssertEqual(recap.totalPhotoCount, 1)
        XCTAssertEqual(recap.months.first?.photoIDs.first, y2025.id)
    }

    func testYearlyTitle() {
        XCTAssertEqual(MemoryRecapLogic.yearlyTitle(year: 2025), "2025 年度回忆")
    }

    func testEmptyYear() {
        let recap = MemoryRecapLogic.yearlyRecap(photos: [], year: 2025)
        XCTAssertTrue(recap.months.isEmpty)
        XCTAssertTrue(recap.heroPhotoIDs.isEmpty)
        XCTAssertEqual(recap.totalPhotoCount, 0)
    }
}

// MARK: - ExportQuality

final class ExportQualityTests: XCTestCase {

    func testStandardMetadata() {
        XCTAssertEqual(ExportQuality.standard.maxLongEdgePixels, 1080)
        XCTAssertEqual(ExportQuality.standard.jpegCompressionQuality, 0.9, accuracy: 0.001)
        XCTAssertFalse(ExportQuality.standard.isPremium)
    }

    func testHighMetadata() {
        XCTAssertEqual(ExportQuality.high.maxLongEdgePixels, 2400)
        XCTAssertEqual(ExportQuality.high.jpegCompressionQuality, 0.95, accuracy: 0.001)
        XCTAssertTrue(ExportQuality.high.isPremium)
    }

    func testResolvedForFreeUser() {
        XCTAssertEqual(ExportQuality.high.resolved(isPro: false), .standard)
        XCTAssertEqual(ExportQuality.standard.resolved(isPro: false), .standard)
    }

    func testResolvedForProUser() {
        XCTAssertEqual(ExportQuality.high.resolved(isPro: true), .high)
        XCTAssertEqual(ExportQuality.standard.resolved(isPro: true), .standard)
    }

    func testScaledSizeDownscalesLongEdge() {
        // 4000×3000 → 长边 4000，缩到 1080
        let standard = ExportQuality.standard.scaledSize(originalWidth: 4000, originalHeight: 3000)
        XCTAssertEqual(standard.width, 1080)
        XCTAssertEqual(standard.height, 810) // 3000 × (1080/4000) = 810
    }

    func testScaledSizeKeepsSmallOriginal() {
        let result = ExportQuality.high.scaledSize(originalWidth: 800, originalHeight: 600)
        XCTAssertEqual(result.width, 800)
        XCTAssertEqual(result.height, 600)
    }

    func testScaledSizePortraitImage() {
        // 竖图 3000×4000 → 长边 4000 缩到 1080
        let standard = ExportQuality.standard.scaledSize(originalWidth: 3000, originalHeight: 4000)
        XCTAssertEqual(standard.height, 1080)
        XCTAssertEqual(standard.width, 810)
    }

    func testScaledSizeHighQualityLargerLimit() {
        let high = ExportQuality.high.scaledSize(originalWidth: 4000, originalHeight: 3000)
        XCTAssertEqual(high.width, 2400)
        XCTAssertEqual(high.height, 1800)
    }
}
