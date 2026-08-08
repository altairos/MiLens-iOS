import XCTest
@testable import MiLensKit
// 显式绑定 RGBColor：macOS 上 Quickdraw（经 XCTest→AppKit 传递导入）有同名 C struct，
// 不限定会报 ambiguous；Linux/WSL2 无此冲突。
import struct MiLensKit.RGBColor

/// BeadPaletteSelection 测试。翻译自源端 shared/.../test/BeadPaletteSelection.test.ets。
final class BeadPaletteSelectionTests: XCTestCase {

    private func color(_ id: String, _ red: Int, _ green: Int, _ blue: Int,
                       tags: [BeadColorTag]? = nil) -> BeadColor {
        return BeadColor(id: id, name: id, rgb: RGBColor(red, green, blue),
                         symbol: id, brand: "test", tags: tags)
    }

    private func rgba(_ values: [[Int]]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: values.count * 4)
        for i in 0..<values.count {
            result[i * 4] = UInt8(values[i][0])
            result[i * 4 + 1] = UInt8(values[i][1])
            result[i * 4 + 2] = UInt8(values[i][2])
            result[i * 4 + 3] = UInt8(values[i][3])
        }
        return result
    }

    func testReturnsNeutralFallbackWhenEverySampleIsUnavailable() {
        let pixels = rgba([[255, 0, 0, 0], [0, 0, 0, 255]])
        let dominant = medianCutExtract(pixels: pixels, pixelCount: 2, targetColors: 4,
                                        empty: [0, 1])
        XCTAssertEqual(dominant.count, 1)
        XCTAssertLessThan(abs(dominant[0].a), 1)
        XCTAssertLessThan(abs(dominant[0].b), 1)
    }

    func testSplitsDistinctDarkAndLightSamplesIntoSeparateDominantColors() {
        let pixels = rgba([[10, 10, 10, 255], [20, 20, 20, 255],
                           [230, 230, 230, 255], [240, 240, 240, 255]])
        let dominant = medianCutExtract(pixels: pixels, pixelCount: 4, targetColors: 2)
        XCTAssertEqual(dominant.count, 2)
        XCTAssertGreaterThan(abs(dominant[0].L - dominant[1].L), 60)
    }

    func testGivesProtectedSamplesMoreInfluenceInSingleColorAverage() {
        let pixels = rgba([[0, 0, 0, 255], [0, 0, 0, 255], [255, 255, 255, 255]])
        let normal = medianCutExtract(pixels: pixels, pixelCount: 3, targetColors: 1)
        let weighted = medianCutExtract(pixels: pixels, pixelCount: 3, targetColors: 1,
                                        protectMask: [0, 0, 1])
        XCTAssertGreaterThan(weighted[0].L, normal[0].L)
    }

    func testPenalizesAvoidForFurColorsAndRewardsWarmPetColors() {
        let source = LabColor(L: 60, a: 12, b: 18)
        let candidate = LabColor(L: 60, a: 12, b: 18)
        let avoided = color("avoid", 150, 100, 80, tags: [.avoidForFur])
        let preferred = color("brown", 150, 100, 80, tags: [.brownFur])
        XCTAssertGreaterThan(
            taggedPaletteDistance(source, candidate, color: avoided, petFriendlyPenalty: 20),
            taggedPaletteDistance(source, candidate, color: preferred, petFriendlyPenalty: 20)
        )
    }

    func testCoversPresentLightnessBucketsWithoutExceedingColorLimit() {
        let palette = [
            color("black", 10, 10, 10), color("gray", 125, 125, 125),
            color("white", 245, 245, 245), color("red", 220, 30, 30)
        ]
        let dominant = [rgbToLab(10, 10, 10), rgbToLab(125, 125, 125), rgbToLab(245, 245, 245)]
        let selected = selectBestPaletteColors(dominantColors: dominant, allPaletteColors: palette,
                                                maxColors: 3, lightnessBucketCoverage: 1,
                                                petFriendlyPenalty: 0)
        let ids = selected.map { $0.id }
        XCTAssertEqual(selected.count, 3)
        XCTAssertTrue(ids.contains("black"))
        XCTAssertTrue(ids.contains("gray"))
        XCTAssertTrue(ids.contains("white"))
    }

    func testReservesNeutralSourceBucketsBeforeChromaticColorsFillReducedPalette() {
        let palette = [
            color("dark", 20, 20, 20), color("mid", 130, 130, 130),
            color("light", 240, 240, 240), color("red", 230, 20, 20)
        ]
        let source = rgba([[20, 20, 20, 255], [130, 130, 130, 255], [240, 240, 240, 255]])
        let selected = selectBestPaletteColors(dominantColors: [rgbToLab(230, 20, 20)],
                                                allPaletteColors: palette,
                                                maxColors: 3, lightnessBucketCoverage: 0,
                                                petFriendlyPenalty: 0,
                                                sourcePixels: source)
        let ids = selected.map { $0.id }
        XCTAssertTrue(ids.contains("dark"))
        XCTAssertTrue(ids.contains("mid"))
        XCTAssertTrue(ids.contains("light"))
        XCTAssertFalse(ids.contains("red"))
    }
}
