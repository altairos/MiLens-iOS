//  PetDisplayLogicTests —— 宠物显示格式化纯逻辑测试
//  （对应源端 DateUtils.test.ets calcAge/calcDaysTogether + Pet.getSpeciesName/getGenderName）。
//
//  翻译源端黄金规格，验证物种/性别/年龄/相处天数的显示文案一致性。

import XCTest
@testable import MiLens

final class PetDisplayLogicTests: XCTestCase {

    // MARK: - 物种显示名（对应源端 getSpeciesName）

    func testSpeciesDisplayName() {
        XCTAssertEqual(PetDisplayLogic.speciesDisplayName(.cat), "喵星人")
        XCTAssertEqual(PetDisplayLogic.speciesDisplayName(.dog), "汪星人")
        XCTAssertEqual(PetDisplayLogic.speciesDisplayName(.unknown), "未知")
    }

    // MARK: - 性别显示名（对应源端 getGenderName）

    func testGenderDisplayName() {
        XCTAssertEqual(PetDisplayLogic.genderDisplayName(.male), "男孩子")
        XCTAssertEqual(PetDisplayLogic.genderDisplayName(.female), "女孩子")
        XCTAssertEqual(PetDisplayLogic.genderDisplayName(.unknown), "未知")
    }

    // MARK: - 年龄格式化（对应源端 calcAge）

    func testAgeTextNilBirthdayReturnsUnknown() {
        XCTAssertEqual(PetDisplayLogic.ageText(from: nil), "未知")
    }

    func testAgeTextSameMonthReturnsZeroMonths() {
        // 对应源端「当月出生应返回 0个月」
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let birthday = cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        XCTAssertEqual(PetDisplayLogic.ageText(from: birthday, now: now, calendar: cal), "0个月")
    }

    func testAgeTextMonthsOnly() {
        // 对应源端「8个月」
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let birthday = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        XCTAssertEqual(PetDisplayLogic.ageText(from: birthday, now: now, calendar: cal), "7个月")
    }

    func testAgeTextExactYears() {
        // 对应源端「3岁」——同月正好整年
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let birthday = cal.date(from: DateComponents(year: 2023, month: 3, day: 1))!
        XCTAssertEqual(PetDisplayLogic.ageText(from: birthday, now: now, calendar: cal), "3岁")
    }

    func testAgeTextYearsAndMonths() {
        // 对应源端「2岁3个月」
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let birthday = cal.date(from: DateComponents(year: 2024, month: 3, day: 1))!
        XCTAssertEqual(PetDisplayLogic.ageText(from: birthday, now: now, calendar: cal), "2岁3个月")
    }

    // MARK: - 相处天数（对应源端 calcDaysTogether）

    func testDaysTogetherNilReturnsZero() {
        XCTAssertEqual(PetDisplayLogic.daysTogether(from: nil), 0)
    }

    func testDaysTogetherTodayReturnsZero() {
        let now = Date()
        XCTAssertEqual(PetDisplayLogic.daysTogether(from: now, now: now), 0)
    }

    func testDaysTogetherOneDayAgo() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        let days = PetDisplayLogic.daysTogether(from: yesterday, now: now)
        XCTAssertEqual(days, 1)
    }

    func testDaysTogetherTenDaysAgo() {
        let now = Date()
        let tenDaysAgo = now.addingTimeInterval(-10 * 86_400)
        let days = PetDisplayLogic.daysTogether(from: tenDaysAgo, now: now)
        XCTAssertEqual(days, 10)
    }

    func testDaysTogetherFutureReturnsNegative() {
        let now = Date()
        let future = now.addingTimeInterval(10 * 86_400)
        let days = PetDisplayLogic.daysTogether(from: future, now: now)
        XCTAssertEqual(days, -10)
    }

    // MARK: - 日期格式化

    func testDateTextNilReturnsEmpty() {
        XCTAssertEqual(PetDisplayLogic.dateText(nil), "")
    }

    func testDateTextFormatting() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2024, month: 7, day: 3))!
        XCTAssertEqual(PetDisplayLogic.dateText(date), "2024-07-03")
    }
}
