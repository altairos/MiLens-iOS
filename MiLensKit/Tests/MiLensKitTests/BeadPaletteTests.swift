import XCTest
@testable import MiLensKit

/// BeadPalette 查询契约测试。翻译自源端 shared/.../test/BeadPalette.test.ets，
/// 并补充色数/唯一性校验。行为一致性守护。
final class BeadPaletteTests: XCTestCase {

    // MARK: - 源端用例翻译

    func testReturnsKnownPalettesAndNilForUnknownIds() {
        XCTAssertEqual(getBeadPalette("generic_24")?.colors.count, 24)
        XCTAssertEqual(getBeadPalette("pet_basic_96")?.colors.count, 96)
        XCTAssertNil(getBeadPalette("missing"))
    }

    func testAdvertisesUniqueAvailablePaletteIds() {
        let available = getAvailablePalettes()
        let ids = Set(available.map(\.id))
        XCTAssertEqual(ids.count, available.count, "available palette ids must be unique")
        XCTAssertGreaterThanOrEqual(available.count, 4)
    }

    func testFallsBackSafelyForUnknownMardIds() {
        // 未知 setId 回退到全部 291 色（源端 fallback 行为）
        XCTAssertEqual(getMardColorsBySet("missing").count, getMardColorsBySet("MARD_291").count)
        // 未知 subsetId 回退到 96 色
        XCTAssertEqual(getMardPetColors("missing").count, getMardPetColors("MARD_PET_96").count)
    }

    func testProvides96UniqueResolvableColorsInPetPalette() {
        let colors = getMardPetColors("MARD_PET_96")
        XCTAssertEqual(mardPet96Codes.count, 96)
        XCTAssertEqual(Set(mardPet96Codes).count, 96, "PET_96 codes must be unique")
        XCTAssertEqual(colors.count, 96)
        XCTAssertEqual(Set(colors.map(\.id)).count, 96, "resolved pet colors must be unique")
    }

    func testFormatsMardDisplayAndShortCodesForKnownColor() {
        // 源端用 'pet_96' 触发 fallback；等价于 'MARD_PET_96'
        let colors = getMardPetColors("pet_96")
        XCTAssertGreaterThan(colors.count, 0)
        XCTAssertGreaterThan(getMardDisplayText(colors[0]).count, 0)
        XCTAssertGreaterThan(getMardShortCode(colors[0]).count, 0)
    }

    // MARK: - 补充覆盖

    func testStaticPaletteColorCounts() {
        XCTAssertEqual(paletteGeneric24.colors.count, 24)
        XCTAssertEqual(paletteGeneric48.colors.count, 48)
        XCTAssertEqual(palettePetBasic96.colors.count, 96)
        XCTAssertEqual(palettePetFull160.colors.count, 160)
    }

    func testMardAllColorsHas291Entries() {
        XCTAssertEqual(mardAllColors.count, 291, "MARD_ALL_COLORS must have exactly 291 colors")
    }

    func testMardSetSizes() {
        // 套装色号应单调递增（72 < 96 < 120 < 144 < 221 < 291）
        let s72 = getMardColorsBySet("MARD_72").count
        let s96 = getMardColorsBySet("MARD_96").count
        let s120 = getMardColorsBySet("MARD_120").count
        let s144 = getMardColorsBySet("MARD_144").count
        let s221 = getMardColorsBySet("MARD_221").count
        let s291 = getMardColorsBySet("MARD_291").count
        XCTAssertLessThan(s72, s96)
        XCTAssertLessThan(s96, s120)
        XCTAssertLessThan(s120, s144)
        XCTAssertLessThan(s144, s221)
        XCTAssertLessThan(s221, s291)
    }

    func testMardPet160SupersetOfPet96() {
        // PET_160 额外色号去重后应 ≥ 96
        let colors160 = getMardPetColors("MARD_PET_160")
        XCTAssertGreaterThanOrEqual(colors160.count, 96)
    }

    func testGetBeadPaletteMardRoute() {
        // getBeadPalette 应正确路由 MARD 前缀到 MARD 查询
        let p120 = getBeadPalette("MARD_120")
        XCTAssertNotNil(p120)
        XCTAssertEqual(p120?.id, "MARD_120")
        XCTAssertEqual(p120?.colors.count, getMardColorsBySet("MARD_120").count)

        let pet96 = getBeadPalette("MARD_PET_96")
        XCTAssertNotNil(pet96)
        XCTAssertEqual(pet96?.colors.count, getMardPetColors("MARD_PET_96").count)
    }

    func testGetMardDisplayTextForNonMard() {
        let generic = BeadColor(id: "C01", name: "白色", rgb: RGBColor(255, 255, 255), symbol: "A", brand: "generic")
        XCTAssertEqual(getMardDisplayText(generic), "白色")
        XCTAssertEqual(getMardShortCode(generic), "C01")
    }

    func testGetMardPetColorTags() {
        // H1 应有 warm_white + neutral_white 两个标签
        let tags = getMardPetColorTags("H1")
        XCTAssertTrue(tags.contains(.warmWhite))
        XCTAssertTrue(tags.contains(.neutralWhite))
        // 未知色号返回空
        XCTAssertTrue(getMardPetColorTags("ZZ99").isEmpty)
    }
}
