import XCTest
@testable import MiLensKit

//  PetBusinessCardLogic 纯决策逻辑测试（创作 Tab 名片卡项目）。
//
//  无源端黄金规格（名片卡为 iOS 自研创作项目），行为规格由本文件守护：
//  - 校验：简介/标签/主人称呼长度
//  - 标签规范化：去空白/去重保序/过滤超长/截断数量
//  - 组装：端到端数据构建 + 自动规范化
//  - 副标题/身份行/主人行：缺字段跳过分隔符
//  - 档案编号与时间行：MILENS ID、季节行、日期行
//  - BusinessCardTemplate：模板元数据与门控

// MARK: - 校验

final class BusinessCardValidationTests: XCTestCase {

    func testValidateTaglineWithinLimit() {
        XCTAssertTrue(PetBusinessCardLogic.validateTagline("这是一只很可爱的猫咪"))
        XCTAssertTrue(PetBusinessCardLogic.validateTagline(""))
        XCTAssertTrue(PetBusinessCardLogic.validateTagline(String(repeating: "字", count: 20)))
    }

    func testValidateTaglineExceedsLimit() {
        XCTAssertFalse(PetBusinessCardLogic.validateTagline(String(repeating: "字", count: 21)))
    }

    func testValidateTagEmpty() {
        XCTAssertFalse(PetBusinessCardLogic.validateTag(""))
        XCTAssertFalse(PetBusinessCardLogic.validateTag("   "))
    }

    func testValidateTagWithinLimit() {
        XCTAssertTrue(PetBusinessCardLogic.validateTag("活泼"))
        XCTAssertTrue(PetBusinessCardLogic.validateTag(String(repeating: "字", count: 6)))
    }

    func testValidateTagExceedsLimit() {
        XCTAssertFalse(PetBusinessCardLogic.validateTag(String(repeating: "字", count: 7)))
    }

    func testValidateOwnerName() {
        XCTAssertTrue(PetBusinessCardLogic.validateOwnerName("小橘妈妈"))
        XCTAssertTrue(PetBusinessCardLogic.validateOwnerName(""))
        XCTAssertFalse(PetBusinessCardLogic.validateOwnerName(String(repeating: "字", count: 13)))
    }
}

// MARK: - 标签规范化

final class BusinessCardNormalizeTagsTests: XCTestCase {

    func testDeduplicatesPreservingOrder() {
        let result = PetBusinessCardLogic.normalizeTags(["活泼", "黏人", "活泼", "贪吃"])
        XCTAssertEqual(result, ["活泼", "黏人", "贪吃"])
    }

    func testTrimsWhitespace() {
        let result = PetBusinessCardLogic.normalizeTags(["  活泼  ", "黏人"])
        XCTAssertEqual(result, ["活泼", "黏人"])
    }

    func testFiltersEmptyAndOversize() {
        // 7 字超过 maxTagLength=6，应被过滤
        let oversize = String(repeating: "字", count: 7)
        let result = PetBusinessCardLogic.normalizeTags(["", "   ", oversize, "活泼"])
        XCTAssertEqual(result, ["活泼"])
    }

    func testCapsAtMaxCount() {
        let input = ["活泼", "黏人", "贪吃", "高冷", "好奇", "温顺"]
        let result = PetBusinessCardLogic.normalizeTags(input)
        XCTAssertEqual(result.count, PetBusinessCardLogic.maxTagCount)
        XCTAssertEqual(result, ["活泼", "黏人", "贪吃", "高冷"])
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(PetBusinessCardLogic.normalizeTags([]).isEmpty)
    }
}

// MARK: - 数据组装

final class BusinessCardBuildDataTests: XCTestCase {

    private func makePet() -> PetBusinessCardInput {
        PetBusinessCardInput(
            id: UUID(), name: "咪咪", speciesName: "喵星人", breed: "橘猫",
            genderName: "男生", ageText: "3岁", avatarPath: "/photos/mimi.jpg")
    }

    func testBuildDataEndToEnd() {
        let pet = makePet()
        let data = PetBusinessCardLogic.buildData(
            from: pet,
            tags: ["活泼", "黏人", "活泼"],
            tagline: "家里的开心果",
            ownerName: "小橘妈妈"
        )
        XCTAssertEqual(data.petID, pet.id)
        XCTAssertEqual(data.name, "咪咪")
        XCTAssertEqual(data.speciesName, "喵星人")
        XCTAssertEqual(data.breed, "橘猫")
        XCTAssertEqual(data.tags, ["活泼", "黏人"])
        XCTAssertEqual(data.tagline, "家里的开心果")
        XCTAssertEqual(data.ownerName, "小橘妈妈")
    }

    func testBuildDataAutoTruncatesTagline() {
        let longTagline = String(repeating: "字", count: 30)
        let data = PetBusinessCardLogic.buildData(
            from: makePet(), tags: [], tagline: longTagline, ownerName: "")
        XCTAssertEqual(data.tagline.count, PetBusinessCardLogic.maxTaglineLength)
    }

    func testBuildDataAutoNormalizesTags() {
        let data = PetBusinessCardLogic.buildData(
            from: makePet(),
            tags: ["", "活泼", "活泼", String(repeating: "字", count: 10), "黏人"],
            tagline: "", ownerName: "")
        XCTAssertEqual(data.tags, ["活泼", "黏人"])
    }

    func testBuildDataDerivesArchiveLines() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let birthday = calendar.date(from: DateComponents(year: 2022, month: 5, day: 21))!
        let pet = PetBusinessCardInput(
            id: UUID(), name: "咪咪", speciesName: "喵星人", breed: "橘猫",
            genderName: "男生", ageText: "3岁", avatarPath: "",
            birthday: birthday, profileCreatedAt: birthday)
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
        let data = PetBusinessCardLogic.buildData(
            from: pet, tags: [], tagline: "", ownerName: "", now: now, calendar: calendar)
        XCTAssertEqual(data.identityLine, "喵星人 · 3岁 · 男生")
#if os(Linux)
        // Linux（WSL2）无 CFStringTransform，拼音首字母不可用：回退首个字母字符（咪咪 → 咪）
        XCTAssertEqual(data.milensID, "咪—0521")
#else
        XCTAssertEqual(data.milensID, "MM—0521")
#endif
        XCTAssertEqual(data.seasonLine, "2026 · 夏")
        XCTAssertEqual(data.shotDateLine, "2026.08.14")
    }

    func testExportSizeIs16x10Landscape() {
        XCTAssertEqual(PetBusinessCardLogic.exportWidth, 1440)
        XCTAssertEqual(PetBusinessCardLogic.exportHeight, 900)
        let ratio = Double(PetBusinessCardLogic.exportWidth) / Double(PetBusinessCardLogic.exportHeight)
        XCTAssertEqual(ratio, 1.6, accuracy: 0.001)
    }
}

// MARK: - 副标题与主人行

final class BusinessCardSubtitleTests: XCTestCase {

    func testSubtitleWithAllFields() {
        let line = PetBusinessCardLogic.subtitleLine(
            speciesName: "喵星人", breed: "橘猫", genderName: "男生", ageText: "3岁")
        XCTAssertEqual(line, "喵星人 · 橘猫 · 男生 · 3岁")
    }

    func testSubtitleSkipsEmptyFields() {
        let line = PetBusinessCardLogic.subtitleLine(
            speciesName: "喵星人", breed: "", genderName: "", ageText: "3岁")
        XCTAssertEqual(line, "喵星人 · 3岁")
    }

    func testSubtitleAllEmptyReturnsEmpty() {
        let line = PetBusinessCardLogic.subtitleLine(
            speciesName: "", breed: "", genderName: "", ageText: "")
        XCTAssertEqual(line, "")
    }

    func testOwnerLineWithContent() {
        XCTAssertEqual(PetBusinessCardLogic.ownerLine("小橘妈妈"), "照护人｜小橘妈妈")
    }

    func testOwnerLineEmpty() {
        XCTAssertEqual(PetBusinessCardLogic.ownerLine(""), "")
    }

    func testIdentityLineWithAllFields() {
        let line = PetBusinessCardLogic.identityLine(
            speciesName: "喵星人", ageText: "3岁", genderName: "男生")
        XCTAssertEqual(line, "喵星人 · 3岁 · 男生")
    }

    func testIdentityLineSkipsEmptyFields() {
        let line = PetBusinessCardLogic.identityLine(
            speciesName: "喵星人", ageText: "", genderName: "男生")
        XCTAssertEqual(line, "喵星人 · 男生")
    }
}

// MARK: - 档案编号与时间行

final class BusinessCardMilensIDTests: XCTestCase {

    /// 固定格里历 + 上海时区，避免 CI 时区差异导致跨日抖动。
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

#if !os(Linux)
    // 拼音首字母依赖 CFStringTransform（仅 Apple 平台）；Linux（WSL2）下跳过。
    func testChineseNameUsesPinyinInitials() {
        let id = PetBusinessCardLogic.milensID(
            name: "小满", birthday: date(2022, 5, 21), fallbackDate: nil, calendar: calendar)
        XCTAssertEqual(id, "XM—0521")
    }

    func testMissingBirthdayFallsBackToProfileCreatedAt() {
        let id = PetBusinessCardLogic.milensID(
            name: "小满", birthday: nil, fallbackDate: date(2024, 11, 3), calendar: calendar)
        XCTAssertEqual(id, "XM—1103")
    }
#endif

    func testNonChineseNameUsesFirstLetter() {
        let id = PetBusinessCardLogic.milensID(
            name: "Luna", birthday: date(2022, 5, 21), fallbackDate: nil, calendar: calendar)
        XCTAssertEqual(id, "L—0521")
    }

    func testEmptyWhenNameOrDateUnresolvable() {
        XCTAssertEqual(
            PetBusinessCardLogic.milensID(
                name: "", birthday: date(2022, 5, 21), fallbackDate: nil, calendar: calendar),
            "")
        XCTAssertEqual(
            PetBusinessCardLogic.milensID(
                name: "小满", birthday: nil, fallbackDate: nil, calendar: calendar),
            "")
    }

    func testSeasonLineMapsMonths() {
        XCTAssertEqual(PetBusinessCardLogic.seasonLine(from: date(2026, 3, 1), calendar: calendar), "2026 · 春")
        XCTAssertEqual(PetBusinessCardLogic.seasonLine(from: date(2026, 8, 14), calendar: calendar), "2026 · 夏")
        XCTAssertEqual(PetBusinessCardLogic.seasonLine(from: date(2026, 9, 30), calendar: calendar), "2026 · 秋")
        XCTAssertEqual(PetBusinessCardLogic.seasonLine(from: date(2026, 12, 2), calendar: calendar), "2026 · 冬")
    }

    func testShotDateLine() {
        XCTAssertEqual(
            PetBusinessCardLogic.shotDateLine(from: date(2026, 8, 14), calendar: calendar),
            "2026.08.14")
    }
}

// MARK: - 预设标签

final class BusinessCardPresetTagsTests: XCTestCase {

    func testAvailableTagsNotEmpty() {
        XCTAssertFalse(PetBusinessCardLogic.availableTags.isEmpty)
    }

    func testAllPresetTagsPassValidation() {
        for tag in PetBusinessCardLogic.availableTags {
            XCTAssertTrue(PetBusinessCardLogic.validateTag(tag), "预设标签「\(tag)」未通过自身校验")
        }
    }

    func testAvailableTagsAreUnique() {
        let tags = PetBusinessCardLogic.availableTags
        XCTAssertEqual(Set(tags).count, tags.count, "预设标签不应重复")
    }
}

// MARK: - BusinessCardTemplate 元数据

final class BusinessCardTemplateTests: XCTestCase {

    func testAllTemplatesPresent() {
        XCTAssertEqual(
            BusinessCardTemplate.allCases.map(\.rawValue),
            ["museum", "binding", "gallery", "darkroom"]
        )
    }

    func testMuseumIsFree() {
        XCTAssertFalse(BusinessCardTemplate.museum.isPremium)
        XCTAssertTrue(BusinessCardTemplate.binding.isPremium)
        XCTAssertTrue(BusinessCardTemplate.gallery.isPremium)
        XCTAssertTrue(BusinessCardTemplate.darkroom.isPremium)
    }

    func testResolveForFreeUser() {
        XCTAssertEqual(BusinessCardTemplate.resolve(.binding, isPro: false), .museum)
        XCTAssertEqual(BusinessCardTemplate.resolve(.museum, isPro: false), .museum)
    }

    func testResolveForProUser() {
        XCTAssertEqual(BusinessCardTemplate.resolve(.binding, isPro: true), .binding)
        XCTAssertEqual(BusinessCardTemplate.resolve(.museum, isPro: true), .museum)
    }

    func testIsUsable() {
        XCTAssertTrue(BusinessCardTemplate.museum.isUsable(isPro: false))
        XCTAssertFalse(BusinessCardTemplate.binding.isUsable(isPro: false))
        XCTAssertTrue(BusinessCardTemplate.binding.isUsable(isPro: true))
    }

    func testLocalizationKey() {
        XCTAssertEqual(BusinessCardTemplate.museum.localizationKey, "businessCard.template.museum")
        XCTAssertEqual(BusinessCardTemplate.darkroom.localizationKey, "businessCard.template.darkroom")
    }

    func testFreeDefault() {
        XCTAssertEqual(BusinessCardTemplate.freeDefault, .museum)
    }
}
