import XCTest
@testable import MiLensKit

//  GrowthCompareLogic 纯决策逻辑测试（ADR-0010 §3.3 / §10.11）。
//
//  无源端黄金规格（成长对比为 iOS 自研情感触点），行为规格由本文件守护：
//  - 排序：按 takenAt 升序（nil 落后、同序稳定）
//  - 时间标签：有生日→年龄（岁+月）；无生日→日期回退；无 takenAt→「未知」
//  - 间隔标签：年+月 / 仅月 / 不足月按天
//  - 结果构建：端到端有序对 + 标签
//
//  全部日期用固定 UTC Calendar（miLensUTCCalendar）构造，任意时区可复现。

private enum GrowthCompareTestSupport {
    static func makeDate(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return miLensUTCCalendar.date(from: comps)!
    }
}

// MARK: - 排序

final class GrowthCompareOrderingTests: XCTestCase {

    func testOrdersByTakenAtAscending() {
        let early = GrowthComparePhoto(id: UUID(), takenAt: GrowthCompareTestSupport.makeDate(2024, 3))
        let late = GrowthComparePhoto(id: UUID(), takenAt: GrowthCompareTestSupport.makeDate(2025, 8))
        let result = GrowthCompareLogic.orderedPair(late, early)
        XCTAssertEqual(result.early.id, early.id)
        XCTAssertEqual(result.late.id, late.id)
    }

    func testKeepsOrderWhenAlreadyAscending() {
        let early = GrowthComparePhoto(id: UUID(), takenAt: GrowthCompareTestSupport.makeDate(2024, 3))
        let late = GrowthComparePhoto(id: UUID(), takenAt: GrowthCompareTestSupport.makeDate(2025, 8))
        let result = GrowthCompareLogic.orderedPair(early, late)
        XCTAssertEqual(result.early.id, early.id)
        XCTAssertEqual(result.late.id, late.id)
    }

    func testNilTakenAtTreatedAsLatest() {
        let withDate = GrowthComparePhoto(id: UUID(), takenAt: GrowthCompareTestSupport.makeDate(2024, 3))
        let noDate = GrowthComparePhoto(id: UUID(), takenAt: nil)
        let result = GrowthCompareLogic.orderedPair(noDate, withDate)
        XCTAssertEqual(result.early.id, withDate.id)
        XCTAssertEqual(result.late.id, noDate.id)
    }

    func testBothNilKeepsOriginalOrder() {
        let first = GrowthComparePhoto(id: UUID(), takenAt: nil)
        let second = GrowthComparePhoto(id: UUID(), takenAt: nil)
        let result = GrowthCompareLogic.orderedPair(first, second)
        XCTAssertEqual(result.early.id, first.id)
        XCTAssertEqual(result.late.id, second.id)
    }

    func testSameTakenAtKeepsOriginalOrder() {
        let date = GrowthCompareTestSupport.makeDate(2024, 6)
        let first = GrowthComparePhoto(id: UUID(), takenAt: date)
        let second = GrowthComparePhoto(id: UUID(), takenAt: date)
        let result = GrowthCompareLogic.orderedPair(first, second)
        XCTAssertEqual(result.early.id, first.id)
        XCTAssertEqual(result.late.id, second.id)
    }
}

// MARK: - 时间标签

final class GrowthCompareLabelTests: XCTestCase {

    func testAgeLabelYearsAndMonths() {
        // 生日 2023-01 → 拍摄 2024-03 = 1岁2个月
        let birthday = GrowthCompareTestSupport.makeDate(2023, 1)
        let takenAt = GrowthCompareTestSupport.makeDate(2024, 3)
        XCTAssertEqual(GrowthCompareLogic.timeLabel(birthday: birthday, takenAt: takenAt), "1岁2个月")
    }

    func testAgeLabelYearsOnly() {
        let birthday = GrowthCompareTestSupport.makeDate(2023, 3)
        let takenAt = GrowthCompareTestSupport.makeDate(2025, 3)
        XCTAssertEqual(GrowthCompareLogic.timeLabel(birthday: birthday, takenAt: takenAt), "2岁")
    }

    func testAgeLabelMonthsOnly() {
        let birthday = GrowthCompareTestSupport.makeDate(2024, 1)
        let takenAt = GrowthCompareTestSupport.makeDate(2024, 9)
        XCTAssertEqual(GrowthCompareLogic.timeLabel(birthday: birthday, takenAt: takenAt), "8个月")
    }

    func testAgeLabelNewborn() {
        let birthday = GrowthCompareTestSupport.makeDate(2024, 3)
        let takenAt = GrowthCompareTestSupport.makeDate(2024, 3)
        XCTAssertEqual(GrowthCompareLogic.timeLabel(birthday: birthday, takenAt: takenAt), "刚出生")
    }

    func testDateFallbackWhenNoBirthday() {
        let takenAt = GrowthCompareTestSupport.makeDate(2024, 3)
        XCTAssertEqual(GrowthCompareLogic.timeLabel(birthday: nil, takenAt: takenAt), "2024年3月")
    }

    func testUnknownWhenNoTakenAt() {
        XCTAssertEqual(GrowthCompareLogic.timeLabel(birthday: nil, takenAt: nil), "未知")
        let birthday = GrowthCompareTestSupport.makeDate(2023, 1)
        XCTAssertEqual(GrowthCompareLogic.timeLabel(birthday: birthday, takenAt: nil), "未知")
    }
}

// MARK: - 间隔标签

final class GrowthCompareGapTests: XCTestCase {

    func testGapYearsAndMonths() {
        let early = GrowthCompareTestSupport.makeDate(2023, 3)
        let late = GrowthCompareTestSupport.makeDate(2024, 8)
        XCTAssertEqual(GrowthCompareLogic.gapLabel(early: early, late: late), "1年5个月")
    }

    func testGapYearsOnly() {
        let early = GrowthCompareTestSupport.makeDate(2022, 6)
        let late = GrowthCompareTestSupport.makeDate(2025, 6)
        XCTAssertEqual(GrowthCompareLogic.gapLabel(early: early, late: late), "3年")
    }

    func testGapMonthsOnly() {
        let early = GrowthCompareTestSupport.makeDate(2024, 1)
        let late = GrowthCompareTestSupport.makeDate(2024, 7)
        XCTAssertEqual(GrowthCompareLogic.gapLabel(early: early, late: late), "6个月")
    }

    func testGapDaysWhenUnderOneMonth() {
        let early = GrowthCompareTestSupport.makeDate(2024, 3, 1)
        let late = GrowthCompareTestSupport.makeDate(2024, 3, 15)
        // 同月不足一个月 → 按天
        XCTAssertEqual(GrowthCompareLogic.gapLabel(early: early, late: late), "间隔 14 天")
    }

    func testGapEmptyWhenMissingDate() {
        let date = GrowthCompareTestSupport.makeDate(2024, 3)
        XCTAssertEqual(GrowthCompareLogic.gapLabel(early: nil, late: date), "")
        XCTAssertEqual(GrowthCompareLogic.gapLabel(early: date, late: nil), "")
        XCTAssertEqual(GrowthCompareLogic.gapLabel(early: nil, late: nil), "")
    }

    func testGapZeroWhenSameMonth() {
        let date = GrowthCompareTestSupport.makeDate(2024, 3, 10)
        XCTAssertEqual(GrowthCompareLogic.gapLabel(early: date, late: date), "间隔 0 天")
    }
}

// MARK: - 结果构建

final class GrowthCompareResultTests: XCTestCase {

    func testBuildResultEndToEnd() {
        let birthday = GrowthCompareTestSupport.makeDate(2023, 1)
        let early = GrowthComparePhoto(id: UUID(), takenAt: GrowthCompareTestSupport.makeDate(2023, 8))
        let late = GrowthComparePhoto(id: UUID(), takenAt: GrowthCompareTestSupport.makeDate(2025, 1))

        let result = GrowthCompareLogic.buildResult(early: late, late: early, birthday: birthday)

        // 传入顺序相反，结果仍按时间排序
        XCTAssertEqual(result.earlyPhotoID, early.id)
        XCTAssertEqual(result.latePhotoID, late.id)
        XCTAssertEqual(result.earlyLabel, "7个月")
        XCTAssertEqual(result.lateLabel, "2岁")
        XCTAssertEqual(result.gapLabel, "1年5个月")
    }

    func testBuildResultWithDateFallback() {
        let early = GrowthComparePhoto(id: UUID(), takenAt: GrowthCompareTestSupport.makeDate(2024, 3))
        let late = GrowthComparePhoto(id: UUID(), takenAt: GrowthCompareTestSupport.makeDate(2025, 8))

        let result = GrowthCompareLogic.buildResult(early: early, late: late, birthday: nil)

        XCTAssertEqual(result.earlyPhotoID, early.id)
        XCTAssertEqual(result.latePhotoID, late.id)
        XCTAssertEqual(result.earlyLabel, "2024年3月")
        XCTAssertEqual(result.lateLabel, "2025年8月")
        XCTAssertEqual(result.gapLabel, "1年5个月")
    }

    func testExportSizeMatchesPetCardRatio() {
        // 4:5 竖版，与 PetCardLogic.exportSize 同比例
        let ratio = Double(GrowthCompareLogic.exportWidth) / Double(GrowthCompareLogic.exportHeight)
        XCTAssertEqual(ratio, 1080.0 / 1350.0, accuracy: 0.001)
    }
}
