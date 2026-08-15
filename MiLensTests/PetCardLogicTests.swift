//  PetCardLogicTests —— 宠物卡片文案与模板参数测试（P4）。
//  对应 UI-DESIGN.md §6.6 创作首页「宠物卡片」项目（iOS 自研，源端无对应功能）。

import XCTest
@testable import MiLens
import MiLensKit

final class PetCardLogicTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_752_000_000) // 2025-07-08 18:40 UTC
    private let calendar = PetDateCalendar.gregorian

    private func makePet(
        name: String = "咪咪",
        species: Species = .cat,
        birthday: Date? = nil,
        adoptionDay: Date? = nil
    ) -> Pet {
        Pet(name: name, species: species, birthday: birthday, adoptionDay: adoptionDay)
    }

    // MARK: - 有宠物

    func testContentWithPetAndAdoptionDayUsesAnniversaryLine() {
        // 领养日 100 天前 → 日期行优先「来到家100天」而非拍摄日期（xcstrings 无空格）
        let adoption = fixedNow.addingTimeInterval(-100 * 86_400)
        let pet = makePet(adoptionDay: adoption)
        let content = PetCardLogic.content(
            pet: pet, takenAt: fixedNow, now: fixedNow, calendar: calendar)

        XCTAssertEqual(content.title, "咪咪")
        XCTAssertEqual(content.emoji, "\u{1F431}")
        XCTAssertEqual(content.subtitle, "喵星人", "年龄未知时副标题只显示物种")
        XCTAssertEqual(content.dateLine, "来到家100天")
    }

    func testContentSubtitleIncludesAgeWhenBirthdayKnown() {
        // 生日 3 年 2 个月前的稳定日期（UTC 固定日历，跨时区可复现）
        let birthday = calendar.date(
            from: DateComponents(year: 2022, month: 5, day: 16))!
        let pet = makePet(birthday: birthday)
        let content = PetCardLogic.content(
            pet: pet, takenAt: nil, now: fixedNow, calendar: calendar)

        XCTAssertEqual(content.subtitle, "喵星人 · 3岁2个月")
    }

    func testContentWithoutAdoptionDayFallsBackToTakenDate() {
        let pet = makePet()
        let content = PetCardLogic.content(
            pet: pet, takenAt: fixedNow, now: fixedNow, calendar: calendar)

        XCTAssertEqual(content.dateLine, PetDisplayLogic.dateText(fixedNow, calendar: calendar))
    }

    func testContentDogEmoji() {
        let pet = makePet(species: .dog)
        let content = PetCardLogic.content(
            pet: pet, takenAt: nil, now: fixedNow, calendar: calendar)

        XCTAssertEqual(content.emoji, "\u{1F436}")
        XCTAssertEqual(content.subtitle, "汪星人", "年龄未知时副标题只显示物种")
    }

    // MARK: - 无宠物回退

    func testContentWithoutPetUsesFallbackCopy() {
        let content = PetCardLogic.content(
            pet: nil, takenAt: fixedNow, now: fixedNow, calendar: calendar)

        XCTAssertEqual(content.title, "这一天")
        XCTAssertEqual(content.emoji, "\u{1F43E}")
        XCTAssertEqual(content.subtitle, "值得记住的一天")
        XCTAssertEqual(content.dateLine, PetDisplayLogic.dateText(fixedNow, calendar: calendar))
    }

    func testContentWithoutPetAndNoTakenDateKeepsEmptyDateLine() {
        let content = PetCardLogic.content(
            pet: nil, takenAt: nil, now: fixedNow, calendar: calendar)
        XCTAssertEqual(content.dateLine, "")
    }

    // MARK: - 模板参数

    func testExportSizeIs4x5Portrait() {
        let size = PetCardLogic.exportSize
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1350)
        XCTAssertEqual(Double(size.width) / Double(size.height), 4.0 / 5.0, accuracy: 0.001)
    }

    func testGradientRatioWithinSafeRange() {
        XCTAssertGreaterThan(PetCardLogic.gradientHeightRatio, 0.3)
        XCTAssertLessThan(PetCardLogic.gradientHeightRatio, 0.6)
    }

    // MARK: - kind 驱动文案变体（ADR-0010 §10.11）

    func testMilestoneKindUsesDaysHomeLine() {
        let adoption = fixedNow.addingTimeInterval(-150 * 86_400)
        let pet = makePet(adoptionDay: adoption)
        let content = PetCardLogic.content(
            pet: pet, takenAt: fixedNow, now: fixedNow, calendar: calendar, kind: .milestone)
        // 里程碑与领养日语义同源；文案随相处天数分档，150 天落在「来到家」档
        XCTAssertTrue(content.dateLine.contains("来到家"))
        XCTAssertTrue(content.dateLine.contains("150"))
    }

    func testBirthdayKindUsesBirthdayYearsLine() {
        let birthday = calendar.date(from: DateComponents(year: 2022, month: 7, day: 1))!
        let pet = makePet(birthday: birthday)
        let content = PetCardLogic.content(
            pet: pet, takenAt: fixedNow, now: fixedNow, calendar: calendar, kind: .birthday)
        // fixedNow 2025-07-08，生日 2022-07-01 → 3 岁
        XCTAssertTrue(content.dateLine.contains("3"))
    }

    func testNilKindPreservesExistingBehavior() {
        let adoption = fixedNow.addingTimeInterval(-100 * 86_400)
        let pet = makePet(adoptionDay: adoption)
        let noKind = PetCardLogic.content(
            pet: pet, takenAt: fixedNow, now: fixedNow, calendar: calendar)
        let explicitNil = PetCardLogic.content(
            pet: pet, takenAt: fixedNow, now: fixedNow, calendar: calendar, kind: nil)
        XCTAssertEqual(noKind, explicitNil)
    }
}
