import XCTest
@testable import MiLensKit

//  PetBusinessCardLogic 纯决策逻辑测试（创作 Tab 名片卡项目）。
//
//  无源端黄金规格（名片卡为 iOS 自研创作项目），行为规格由本文件守护：
//  - 校验：简介/标签/主人称呼长度
//  - 标签规范化：去空白/去重保序/过滤超长/截断数量
//  - 组装：端到端数据构建 + 自动规范化
//  - 副标题/主人行：缺字段跳过分隔符
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

    func testExportSizeIs3x4Portrait() {
        let ratio = Double(PetBusinessCardLogic.exportWidth) / Double(PetBusinessCardLogic.exportHeight)
        XCTAssertEqual(ratio, 3.0 / 4.0, accuracy: 0.001)
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
        XCTAssertEqual(PetBusinessCardLogic.ownerLine("小橘妈妈"), "铲屎官：小橘妈妈")
    }

    func testOwnerLineEmpty() {
        XCTAssertEqual(PetBusinessCardLogic.ownerLine(""), "")
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
            ["standard", "elegant", "playful", "minimal"]
        )
    }

    func testStandardIsFree() {
        XCTAssertFalse(BusinessCardTemplate.standard.isPremium)
        XCTAssertTrue(BusinessCardTemplate.elegant.isPremium)
        XCTAssertTrue(BusinessCardTemplate.playful.isPremium)
        XCTAssertTrue(BusinessCardTemplate.minimal.isPremium)
    }

    func testResolveForFreeUser() {
        XCTAssertEqual(BusinessCardTemplate.resolve(.elegant, isPro: false), .standard)
        XCTAssertEqual(BusinessCardTemplate.resolve(.standard, isPro: false), .standard)
    }

    func testResolveForProUser() {
        XCTAssertEqual(BusinessCardTemplate.resolve(.elegant, isPro: true), .elegant)
        XCTAssertEqual(BusinessCardTemplate.resolve(.standard, isPro: true), .standard)
    }

    func testIsUsable() {
        XCTAssertTrue(BusinessCardTemplate.standard.isUsable(isPro: false))
        XCTAssertFalse(BusinessCardTemplate.elegant.isUsable(isPro: false))
        XCTAssertTrue(BusinessCardTemplate.elegant.isUsable(isPro: true))
    }

    func testLocalizationKey() {
        XCTAssertEqual(BusinessCardTemplate.standard.localizationKey, "businessCard.template.standard")
        XCTAssertEqual(BusinessCardTemplate.playful.localizationKey, "businessCard.template.playful")
    }

    func testFreeDefault() {
        XCTAssertEqual(BusinessCardTemplate.freeDefault, .standard)
    }
}
