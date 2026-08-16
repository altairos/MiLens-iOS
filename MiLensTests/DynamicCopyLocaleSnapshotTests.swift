//  DynamicCopyLocaleSnapshotTests —— 动态文案固定 locale 快照测试
//  （docs/Localization-Plan.md §3.6 处理原则 / 工作项 #7.7b）。
//
//  覆盖通知、宠物档案与时间线导出的动态文案（含占位符 / 复数 key）：
//  - 层 1 zh-Hans 完整快照：显式固定 Locale(identifier: "zh_Hans_CN")，
//    断言精确字符串（开发语言查表 + 注入参数 + 注入 now/calendar）。
//  - 层 2 未导入语言回退快照：en_US / de_DE / ja_JP 固定 locale 下，
//    xcstrings 未导入翻译按源语言（zh-Hans）回退，输出应与层 1 完全一致
//    且占位符内容不丢、不崩溃。翻译导入（#4–#6）后本层升级为各语言精确快照。
//
//  技术事实：String(localized:locale:) 的 locale 只影响占位符格式化，
//  不切换查表语言（查表由 bundle 匹配决定）；故层 2 与 zh-Hans 等值断言成立
//  （AnniversaryTimeMachineLogicTests 的中文快照已在 CI 跨宿主语言跑绿佐证）。

import XCTest
@testable import MiLens
import MiLensKit

final class DynamicCopyLocaleSnapshotTests: XCTestCase {

    // 固定 locale 保证跨环境可复现（§3.6「避免只在模拟器人工发现」）。
    private let zh = Locale(identifier: "zh_Hans_CN")
    private let unimportedLocales = [
        Locale(identifier: "en_US"),
        Locale(identifier: "de_DE"),
        Locale(identifier: "ja_JP"),
    ]

    private let fixedNow = Date(timeIntervalSince1970: 1_752_000_000) // 2025-07-08 18:40 UTC
    private let calendar = PetDateCalendar.gregorian

    private func daysAgo(_ days: Int) -> Date {
        fixedNow.addingTimeInterval(-Double(days) * 86_400)
    }

    // MARK: - 层 1：zh-Hans 完整快照（通知文案）

    func testPetAnniversaryNotificationBirthdayZhSnapshot() {
        let out = buildPetAnniversaryNotification(petName: "咪咪", kind: .birthday, locale: zh)
        XCTAssertEqual(out.title, "今天是咪咪的生日")
        XCTAssertEqual(out.body, "去看看咪咪的生日回忆吧。")
    }

    func testPetAnniversaryNotificationAdoptionZhSnapshot() {
        let out = buildPetAnniversaryNotification(petName: "咪咪", kind: .adoption, locale: zh)
        XCTAssertEqual(out.title, "今天是和咪咪成为家人的日子")
        XCTAssertEqual(out.body, "去看看你们一起留下的回忆吧。")
    }

    func testPetMilestoneNotificationZhSnapshot() {
        // 复数 key（notify.milestone.title/body）：zh-Hans 仅 other 变体
        let out = buildPetMilestoneNotification(petName: "咪咪", days: 100, locale: zh)
        XCTAssertEqual(out.title, "来到家100天")
        XCTAssertEqual(out.body, "咪咪已经来到这个家100天了")
    }

    // MARK: - 层 1：zh-Hans 完整快照（宠物档案文案）

    func testSpeciesAndGenderDisplayNamesZhSnapshot() {
        XCTAssertEqual(PetDisplayLogic.speciesDisplayName(.cat, locale: zh), "喵星人")
        XCTAssertEqual(PetDisplayLogic.speciesDisplayName(.dog, locale: zh), "汪星人")
        XCTAssertEqual(PetDisplayLogic.speciesDisplayName(.unknown, locale: zh), "未知")
        XCTAssertEqual(PetDisplayLogic.genderDisplayName(.male, locale: zh), "男孩子")
        XCTAssertEqual(PetDisplayLogic.genderDisplayName(.female, locale: zh), "女孩子")
        XCTAssertEqual(PetDisplayLogic.genderDisplayName(.unknown, locale: zh), "未知")
    }

    func testAgeTextZhSnapshot() {
        XCTAssertEqual(
            PetDisplayLogic.ageText(from: nil, now: fixedNow, calendar: calendar, locale: zh),
            "未知")
        // 生日 2022-05-16 → 月差 38 → 「3岁2个月」（zh join 为空串）
        let aged = calendar.date(from: DateComponents(year: 2022, month: 5, day: 16))!
        XCTAssertEqual(
            PetDisplayLogic.ageText(from: aged, now: fixedNow, calendar: calendar, locale: zh),
            "3岁2个月")
        // 生日 2024-11-01 → 月差 8 → 「8个月」
        let young = calendar.date(from: DateComponents(year: 2024, month: 11, day: 1))!
        XCTAssertEqual(
            PetDisplayLogic.ageText(from: young, now: fixedNow, calendar: calendar, locale: zh),
            "8个月")
    }

    /// 相处文案边界（PetDisplayLogic 文档约定）：
    /// 0–180「来到家」；181–365「相处」；366 起「成为家人」；空名回退「相处」。
    func testCompanionshipTextBoundariesZhSnapshot() {
        func text(_ days: Int, name: String = "咪咪") -> String {
            PetDisplayLogic.companionshipText(petName: name, adoptionDay: daysAgo(days), now: fixedNow, locale: zh)
        }
        XCTAssertEqual(text(0), "来到家0天")
        XCTAssertEqual(text(180), "来到家180天", "180 天为 arrived 上界（含）")
        XCTAssertEqual(text(181), "相处181天", "181 天起切 together")
        XCTAssertEqual(text(365), "相处365天", "365 天为 together 上界（含）")
        XCTAssertEqual(text(366), "和咪咪成为家人366天", "366 天起切 family")
        XCTAssertEqual(text(400, name: ""), "相处400天", "缺宠物名时 family 回退 together")
    }

    func testCompanionshipTextNilAndFutureZhSnapshot() {
        XCTAssertEqual(
            PetDisplayLogic.companionshipText(petName: "咪咪", adoptionDay: nil, now: fixedNow, locale: zh),
            "相处天数未知")
        XCTAssertEqual(
            PetDisplayLogic.companionshipText(petName: "咪咪", adoptionDay: daysAgo(-30), now: fixedNow, locale: zh),
            "相处时间尚未开始")
    }

    // MARK: - 层 1：zh-Hans 完整快照（宠物卡片与时间线导出）

    func testPetCardBirthdayDateLineZhSnapshot() {
        // kind == .birthday → 「N岁生日」（pet.card.birthdayYears 复数 key）
        let birthday = calendar.date(from: DateComponents(year: 2022, month: 7, day: 1))!
        let pet = Pet(name: "咪咪", species: .cat, birthday: birthday)
        XCTAssertEqual(
            PetCardLogic.dateLine(
                takenAt: nil, pet: pet, now: fixedNow, calendar: calendar, locale: zh, kind: .birthday),
            "3岁生日")
    }

    func testTimelineExportDateRangeZhSnapshot() {
        let jan2024 = TimelineMonth(year: 2024, month: 1, yearMonth: "2024-01", isYearStart: true, entries: [])
        let aug2026 = TimelineMonth(year: 2026, month: 8, yearMonth: "2026-08", isYearStart: false, entries: [])

        // 跨月 → 本地化连接符（zh：「空格 em-dash 空格」）
        let multi = TimelineExportLogic.buildExportData(
            months: [jan2024, aug2026], filterTitle: "全部宠物", includeWatermark: true,
            calendar: calendar, locale: zh)
        XCTAssertEqual(multi?.dateRangeText, "2024-01 — 2026-08")

        // 单月 → 原样；空列表 → nil
        let single = TimelineExportLogic.buildExportData(
            months: [jan2024], filterTitle: "全部宠物", includeWatermark: false,
            calendar: calendar, locale: zh)
        XCTAssertEqual(single?.dateRangeText, "2024-01")
        XCTAssertNil(TimelineExportLogic.buildExportData(
            months: [], filterTitle: "全部宠物", includeWatermark: true, calendar: calendar, locale: zh))
    }

    // MARK: - 层 2：未导入语言回退快照（en_US / de_DE / ja_JP）

    /// xcstrings 当前仅含 zh-Hans 翻译：未导入语言按源语言回退，输出与
    /// zh-Hans 快照逐字一致（查表语言不随 locale 参数切换，占位符内容不丢）。
    /// Localization-Plan #4–#6 翻译导入后，本层升级为各语言精确快照。
    func testUnimportedLocalesFallBackToSourceLanguage() {
        for locale in unimportedLocales {
            let id = "locale \(locale.identifier)"

            let milestone = buildPetMilestoneNotification(petName: "咪咪", days: 100, locale: locale)
            XCTAssertEqual(milestone.title, "来到家100天", id)
            XCTAssertEqual(milestone.body, "咪咪已经来到这个家100天了", id)

            let birthday = buildPetAnniversaryNotification(petName: "咪咪", kind: .birthday, locale: locale)
            XCTAssertEqual(birthday.title, "今天是咪咪的生日", id)
            XCTAssertEqual(birthday.body, "去看看咪咪的生日回忆吧。", id)

            let family = PetDisplayLogic.companionshipText(
                petName: "咪咪", adoptionDay: daysAgo(366), now: fixedNow, locale: locale)
            XCTAssertEqual(family, "和咪咪成为家人366天", id)

            let aged = calendar.date(from: DateComponents(year: 2022, month: 5, day: 16))!
            XCTAssertEqual(
                PetDisplayLogic.ageText(from: aged, now: fixedNow, calendar: calendar, locale: locale),
                "3岁2个月", id)
        }
    }
}
