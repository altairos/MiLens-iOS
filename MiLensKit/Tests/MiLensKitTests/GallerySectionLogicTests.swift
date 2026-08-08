//  GallerySectionLogicTests —— 相册按日分组纯逻辑测试。
//
//  行为规格（自建：源端 Gallery 无分组标题，UI-DESIGN.md §5.2 定义）：
//  - 按自然日分组，组间日期倒序（新 → 旧），对齐源端 taken_at DESC 排序约定；
//  - 组内拍摄时间倒序，同时间保持输入顺序（稳定排序）；
//  - 无拍摄时间照片归入末尾「未标注日期」组（title 空串）；
//  - 标题格式「8月7日 · 周三」，月日不补零，weekday 覆盖周日(1)…周六(7)。
//
//  固定 UTC Calendar（miLensUTCCalendar），跨环境可复现。

import XCTest
@testable import MiLensKit

private enum GalleryTestSupport {
    /// 固定 UTC 日期构造器（小时默认 12 时）。
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var dc = DateComponents()
        dc.year = year
        dc.month = month
        dc.day = day
        dc.hour = hour
        return miLensUTCCalendar.date(from: dc)!
    }
}

final class GallerySectionLogicTests: XCTestCase {

    // MARK: - 分组

    func testEmptyInputYieldsNoSections() {
        XCTAssertEqual(GallerySectionLogic.groupPhotos([]), [])
    }

    func testSameDayPhotosGroupIntoSingleSection() {
        let photos = [
            GalleryPhoto(id: UUID(), takenAt: GalleryTestSupport.date(2026, 8, 7, hour: 9)),
            GalleryPhoto(id: UUID(), takenAt: GalleryTestSupport.date(2026, 8, 7, hour: 18)),
            GalleryPhoto(id: UUID(), takenAt: GalleryTestSupport.date(2026, 8, 7, hour: 7)),
        ]
        let sections = GallerySectionLogic.groupPhotos(photos)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].year, 2026)
        XCTAssertEqual(sections[0].month, 8)
        XCTAssertEqual(sections[0].day, 7)
        XCTAssertEqual(sections[0].title, "8月7日 · 周五")
        // 组内拍摄时间倒序：18 时 → 9 时 → 7 时
        XCTAssertEqual(sections[0].photos.map(\.id), [photos[1].id, photos[0].id, photos[2].id])
    }

    func testSectionsOrderedNewestFirst() {
        let older = GalleryPhoto(id: UUID(), takenAt: GalleryTestSupport.date(2026, 8, 1))
        let newer = GalleryPhoto(id: UUID(), takenAt: GalleryTestSupport.date(2026, 8, 7))
        let sections = GallerySectionLogic.groupPhotos([older, newer])
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.map(\.title), ["8月7日 · 周五", "8月1日 · 周六"])
        XCTAssertEqual(sections.map(\.year), [2026, 2026])
        XCTAssertEqual(sections[0].photos.map(\.id), [newer.id])
        XCTAssertEqual(sections[1].photos.map(\.id), [older.id])
    }

    func testSameMonthDayAcrossYearsAreSeparateSections() {
        let photos = [
            GalleryPhoto(id: UUID(), takenAt: GalleryTestSupport.date(2025, 8, 7)),
            GalleryPhoto(id: UUID(), takenAt: GalleryTestSupport.date(2026, 8, 7)),
        ]
        let sections = GallerySectionLogic.groupPhotos(photos)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.map(\.year), [2026, 2025])
        // 同月日跨年各自成组，标题按各自 weekday
        XCTAssertEqual(sections.map(\.title), ["8月7日 · 周五", "8月7日 · 周四"])
    }

    func testUndatedPhotosAppendedAsLastEmptyTitleSection() {
        let dated = GalleryPhoto(id: UUID(), takenAt: GalleryTestSupport.date(2026, 8, 7))
        let undatedA = GalleryPhoto(id: UUID())
        let undatedB = GalleryPhoto(id: UUID())
        let sections = GallerySectionLogic.groupPhotos([undatedA, dated, undatedB])
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "8月7日 · 周五")
        XCTAssertEqual(sections[1].title, "")
        XCTAssertNil(sections[1].year)
        XCTAssertNil(sections[1].month)
        XCTAssertNil(sections[1].day)
        // 无日期组保持输入顺序
        XCTAssertEqual(sections[1].photos.map(\.id), [undatedA.id, undatedB.id])
    }

    func testAllUndatedPhotosSingleSectionKeepsInputOrder() {
        let a = GalleryPhoto(id: UUID())
        let b = GalleryPhoto(id: UUID())
        let c = GalleryPhoto(id: UUID())
        let sections = GallerySectionLogic.groupPhotos([a, b, c])
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "")
        XCTAssertEqual(sections[0].photos.map(\.id), [a.id, b.id, c.id])
    }

    func testMixedDatedAndUndatedSections() {
        let newest = GalleryPhoto(id: UUID(), takenAt: GalleryTestSupport.date(2026, 8, 7))
        let oldest = GalleryPhoto(id: UUID(), takenAt: GalleryTestSupport.date(2025, 6, 1))
        let undated = GalleryPhoto(id: UUID())
        let sections = GallerySectionLogic.groupPhotos([undated, oldest, newest])
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections.map(\.title), ["8月7日 · 周五", "6月1日 · 周日", ""])
    }

    func testStableOrderForEqualTakenAt() {
        let takenAt = GalleryTestSupport.date(2026, 8, 7, hour: 9)
        let a = GalleryPhoto(id: UUID(), takenAt: takenAt)
        let b = GalleryPhoto(id: UUID(), takenAt: takenAt)
        let c = GalleryPhoto(id: UUID(), takenAt: takenAt)
        let sections = GallerySectionLogic.groupPhotos([a, b, c])
        XCTAssertEqual(sections.count, 1)
        // 同拍摄时间保持输入顺序（稳定排序）
        XCTAssertEqual(sections[0].photos.map(\.id), [a.id, b.id, c.id])
    }

    // MARK: - 标题格式

    func testDayTitleFormat() {
        XCTAssertEqual(GallerySectionLogic.dayTitle(year: 2026, month: 8, day: 7), "8月7日 · 周五")
    }

    func testDayTitleWeekdaySundayBoundary() {
        // weekday = 1（周日）边界
        XCTAssertEqual(GallerySectionLogic.dayTitle(year: 2026, month: 8, day: 2), "8月2日 · 周日")
    }

    func testDayTitleWeekdaySaturdayBoundary() {
        // weekday = 7（周六）边界
        XCTAssertEqual(GallerySectionLogic.dayTitle(year: 2026, month: 8, day: 1), "8月1日 · 周六")
    }

    func testDayTitleNoZeroPadding() {
        // 月日不补零：9月5日 而非 09月05日
        XCTAssertEqual(GallerySectionLogic.dayTitle(year: 2026, month: 9, day: 5), "9月5日 · 周六")
    }
}
