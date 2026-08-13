import XCTest
@testable import MiLensKit

// EditorFilterPresetsTests —— 预设滤镜纯逻辑单测。
final class EditorFilterPresetsTests: XCTestCase {

    func testPresetFilterCountIsSix() {
        XCTAssertEqual(PRESET_FILTERS.count, 6)
    }

    func testOriginalPresetIsFirstAndNeutral() {
        XCTAssertEqual(ORIGINAL_PRESET_FILTER.id, "original")
        XCTAssertEqual(PRESET_FILTERS.first?.id, "original")
        XCTAssertTrue(isNeutral(ORIGINAL_PRESET_FILTER.adjustments))
    }

    func testAllPresetsHaveZeroSharpness() {
        // 预设不含锐化：保证点选即时（锐化由手动滑块异步卷积触发）。
        for preset in PRESET_FILTERS {
            XCTAssertEqual(preset.adjustments.sharpness, 0, "\(preset.id) 预设不应含锐化")
        }
    }

    func testPresetIdsAreUnique() {
        let ids = PRESET_FILTERS.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "预设 id 必须唯一")
    }

    func testVividPresetValues() {
        let vivid = PRESET_FILTERS.first { $0.id == "vivid" }
        XCTAssertNotNil(vivid)
        XCTAssertEqual(vivid?.adjustments.contrast, 20)
        XCTAssertEqual(vivid?.adjustments.saturation, 30)
        XCTAssertEqual(vivid?.adjustments.brightness, 0)
    }

    func testMonoPresetIsDesaturated() {
        let mono = PRESET_FILTERS.first { $0.id == "mono" }
        XCTAssertEqual(mono?.adjustments.saturation, -100)
        XCTAssertEqual(mono?.adjustments.contrast, 10)
    }

    // MARK: - matchPresetFilter

    func testMatchReturnsOriginalForNeutralAdjustments() {
        let matched = matchPresetFilter(EditorColorAdjustments())
        XCTAssertEqual(matched?.id, "original")
    }

    func testMatchReturnsVividForExactValues() {
        let matched = matchPresetFilter(EditorColorAdjustments(contrast: 20, saturation: 30))
        XCTAssertEqual(matched?.id, "vivid")
    }

    func testMatchReturnsNilAfterManualTweak() {
        // 手动微调对比度（偏离 vivid 预设）→ 不匹配任何预设
        let matched = matchPresetFilter(EditorColorAdjustments(contrast: 21, saturation: 30))
        XCTAssertNil(matched)
    }

    func testMatchReturnsNilWhenSharpnessNonZero() {
        // 预设 sharpness 恒为 0；手动加锐化后偏离所有预设
        var adj = EditorColorAdjustments(contrast: 20, saturation: 30)
        adj.sharpness = 10
        XCTAssertNil(matchPresetFilter(adj))
    }

    func testMatchReturnsNilForCompletelyCustomValues() {
        let matched = matchPresetFilter(EditorColorAdjustments(brightness: 5, contrast: 5))
        XCTAssertNil(matched)
    }

    func testEveryPresetMatchesItself() {
        // 守卫：每个预设的 adjustments 精确匹配自身（防止预设间参数雷同导致错配）
        for preset in PRESET_FILTERS {
            let matched = matchPresetFilter(preset.adjustments)
            XCTAssertEqual(matched?.id, preset.id, "\(preset.id) 应匹配自身")
        }
    }
}
