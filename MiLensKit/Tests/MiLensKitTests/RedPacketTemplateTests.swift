import XCTest
@testable import MiLensKit

// RedPacketTemplateTests — 模板完整性测试（对应红包封面开发计划 §7 Phase 0 验收）。
final class RedPacketTemplateTests: XCTestCase {

    // MARK: - 目录完整性

    func testCatalogHasFourTemplates() {
        XCTAssertEqual(RedPacketTemplateCatalog.all.count, 4)
    }

    func testAllTemplateIDsAreUnique() {
        let ids = RedPacketTemplateCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "模板 ID 不应重复")
    }

    func testFindByID() {
        let template = RedPacketTemplateCatalog.find(id: "new_year_red")
        XCTAssertNotNil(template)
        XCTAssertEqual(template?.id, "new_year_red")
    }

    func testFindNonExistentReturnsNil() {
        XCTAssertNil(RedPacketTemplateCatalog.find(id: "non_existent"))
    }

    // MARK: - 单个模板完整性

    func testAllTemplatesHaveNonEmptyID() {
        for template in RedPacketTemplateCatalog.all {
            XCTAssertFalse(template.id.isEmpty, "模板 ID 不应为空")
        }
    }

    func testAllTemplatesHavePositiveRevision() {
        for template in RedPacketTemplateCatalog.all {
            XCTAssertGreaterThan(template.revision, 0, "模板版本号应 > 0")
        }
    }

    func testAllTemplatesHaveNonEmptyDisplayName() {
        for template in RedPacketTemplateCatalog.all {
            XCTAssertFalse(template.displayName.isEmpty, "显示名不应为空")
        }
    }

    func testAllTemplatesHaveNonEmptyDisplayNameKey() {
        for template in RedPacketTemplateCatalog.all {
            XCTAssertFalse(template.displayNameKey.isEmpty, "本地化 key 不应为空")
        }
    }

    func testAllTemplatesHaveNonEmptyDescriptionKey() {
        for template in RedPacketTemplateCatalog.all {
            XCTAssertFalse(template.descriptionKey.isEmpty, "描述 key 不应为空")
        }
    }

    // MARK: - 安全区与风险区

    func testAllTemplatesHaveNonEmptySafeZone() {
        for template in RedPacketTemplateCatalog.all {
            XCTAssertGreaterThan(template.safeZone.width, 0, "安全区宽度应 > 0")
            XCTAssertGreaterThan(template.safeZone.height, 0, "安全区高度应 > 0")
        }
    }

    func testAllTemplatesSafeZoneWithinCanvas() {
        for template in RedPacketTemplateCatalog.all {
            let zone = template.safeZone
            XCTAssertGreaterThanOrEqual(zone.x, 0)
            XCTAssertGreaterThanOrEqual(zone.y, 0)
            XCTAssertLessThanOrEqual(zone.x + zone.width, 1.0)
            XCTAssertLessThanOrEqual(zone.y + zone.height, 1.0)
        }
    }

    // MARK: - 默认变换在画布内

    func testDefaultPetTransformWithinCanvas() {
        let cw = RedPacketTemplateCatalog.canvasWidth
        let ch = RedPacketTemplateCatalog.canvasHeight
        for template in RedPacketTemplateCatalog.all {
            let t = template.defaultPetTransform
            XCTAssertGreaterThanOrEqual(t.x, 0)
            XCTAssertLessThanOrEqual(t.x, cw)
            XCTAssertGreaterThanOrEqual(t.y, 0)
            XCTAssertLessThanOrEqual(t.y, ch)
            XCTAssertGreaterThan(t.scale, 0)
        }
    }

    func testDefaultTextPositionWithinCanvas() {
        let cw = RedPacketTemplateCatalog.canvasWidth
        let ch = RedPacketTemplateCatalog.canvasHeight
        for template in RedPacketTemplateCatalog.all {
            let t = template.defaultTextPosition
            XCTAssertGreaterThanOrEqual(t.x, 0)
            XCTAssertLessThanOrEqual(t.x, cw)
            XCTAssertGreaterThanOrEqual(t.y, 0)
            XCTAssertLessThanOrEqual(t.y, ch)
        }
    }

    // MARK: - 推荐配饰分类

    func testAllTemplatesHaveRecommendedCategories() {
        for template in RedPacketTemplateCatalog.all {
            XCTAssertFalse(template.recommendedAccessoryCategories.isEmpty,
                          "推荐配饰分类不应为空")
        }
    }

    // MARK: - 免费模板

    func testFirstTemplateIsFree() {
        XCTAssertTrue(RedPacketTemplateCatalog.all.first?.isFree ?? false,
                     "首套模板应为免费")
    }

    func testFirstFreeTemplateIsNewYearRed() {
        XCTAssertEqual(RedPacketTemplateCatalog.firstFreeTemplate.id, "new_year_red")
    }

    // MARK: - 文本样式预置

    func testAllTextStylePresetsHaveValidStyle() {
        for preset in RedPacketTextStylePreset.allCases {
            let style = preset.style
            XCTAssertFalse(style.fontFamily.isEmpty, "\(preset) 字体族不应为空")
            XCTAssertGreaterThan(style.fontSizeRatio, 0, "\(preset) 字号比例应 > 0")
            XCTAssertFalse(style.colorHex.isEmpty, "\(preset) 颜色不应为空")
        }
    }

    // MARK: - Codable 往返

    func testTemplateCodableRoundTrip() throws {
        for template in RedPacketTemplateCatalog.all {
            let data = try JSONEncoder().encode(template)
            let decoded = try JSONDecoder().decode(RedPacketTemplate.self, from: data)
            XCTAssertEqual(decoded, template)
        }
    }
}
