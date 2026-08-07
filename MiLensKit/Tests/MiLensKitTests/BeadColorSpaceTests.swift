import XCTest
@testable import MiLensKit

/// BeadColorSpace 测试。翻译自源端 shared/.../test/BeadColorSpace.test.ets，
/// 并补充 paletteMatchDistance / precomputePaletteLab 的直接覆盖。行为一致性守护。
final class BeadColorSpaceTests: XCTestCase {

    // 源端 assertChannelNear：通道误差 ≤ 1。
    private func assertChannelNear(_ actual: Int, _ expected: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(actual - expected), 1, file: file, line: line)
    }

    // MARK: - 源端用例翻译

    func testRoundTripsRepresentativeRGBThroughLab() {
        // 源端：[[0,0,0],[255,255,255],[220,30,50],[12,130,240]]
        let colors: [(Int, Int, Int)] = [(0, 0, 0), (255, 255, 255), (220, 30, 50), (12, 130, 240)]
        for (r, g, b) in colors {
            let lab = rgbToLab(Double(r), Double(g), Double(b))
            let roundTrip = labToRgb(lab.L, lab.a, lab.b)
            assertChannelNear(roundTrip.r, r)
            assertChannelNear(roundTrip.g, g)
            assertChannelNear(roundTrip.b, b)
        }
    }

    func testDeltaEIsSymmetricAndZeroForIdenticalColors() {
        let first = LabColor(L: 50, a: 12, b: -8)
        let second = LabColor(L: 65, a: -4, b: 20)
        XCTAssertEqual(deltaE76(first, first), 0, accuracy: 1e-9)
        XCTAssertEqual(deltaE76(first, second), deltaE76(second, first), accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(weightedDeltaE(first, second), deltaE76(first, second))
    }

    func testLabChromaIgnoresLightness() {
        XCTAssertEqual(labChroma(LabColor(L: 10, a: 3, b: 4)), 5, accuracy: 1e-9)
        XCTAssertEqual(labChroma(LabColor(L: 90, a: 3, b: 4)), 5, accuracy: 1e-9)
    }

    func testNearestColorReturnsMatchingPaletteEntry() {
        let palette = [LabColor(L: 20, a: 0, b: 0), LabColor(L: 80, a: 0, b: 0)]
        let result = findNearestBeadColor(79, 0, 0, paletteLab: palette)
        XCTAssertEqual(result.index, 1)
        XCTAssertGreaterThan(result.distance, 0)
    }

    // MARK: - 补充覆盖

    func testPrecomputePaletteLab() {
        let colors = [
            BeadColor(id: "A", name: "红", rgb: RGBColor(220, 30, 50), symbol: "A", brand: "MARD"),
            BeadColor(id: "B", name: "蓝", rgb: RGBColor(12, 130, 240), symbol: "B", brand: "MARD"),
        ]
        let lab = precomputePaletteLab(colors)
        XCTAssertEqual(lab.count, 2)
        // 验证转换非平凡且可复现：与直接 rgbToLab 逐字段比对。
        let expected0 = rgbToLab(220, 30, 50)
        XCTAssertEqual(lab[0].L, expected0.L, accuracy: 1e-9)
        XCTAssertEqual(lab[0].a, expected0.a, accuracy: 1e-9)
        XCTAssertEqual(lab[0].b, expected0.b, accuracy: 1e-9)
        let expected1 = rgbToLab(12, 130, 240)
        XCTAssertEqual(lab[1].L, expected1.L, accuracy: 1e-9)
        XCTAssertEqual(lab[1].a, expected1.a, accuracy: 1e-9)
        XCTAssertEqual(lab[1].b, expected1.b, accuracy: 1e-9)
    }

    func testPaletteMatchDistanceIdenticalIsWeightedDeltaE() {
        let source = LabColor(L: 50, a: 20, b: -15)
        let base = weightedDeltaE(source, source)
        // 相同色：各项保护均不触发（chroma 高但有 hueSimilarity=1 ≥ 0.2），结果应等于 base。
        XCTAssertEqual(paletteMatchDistance(source, source), base, accuracy: 1e-9)
    }

    func testWhiteFurGuardsAgainstBlueCandidate() {
        // 近白源色（高 L、低 chroma）匹配偏蓝候选时，距离应被显著惩罚。
        let nearWhite = rgbToLab(245, 245, 240)   // 近白、近中性
        let blueCandidate = LabColor(L: nearWhite.L - 2, a: -5, b: -12)  // 偏蓝
        let neutralCandidate = LabColor(L: nearWhite.L, a: 0, b: 1)      // 中性
        let distBlue = paletteMatchDistance(nearWhite, blueCandidate)
        let distNeutral = paletteMatchDistance(nearWhite, neutralCandidate)
        // 偏蓝候选距离应明显大于中性候选（白毛保护）。
        XCTAssertGreaterThan(distBlue, distNeutral * 1.5)
    }

    func testFindNearestBeadColorRgbMatchesLabEntry() {
        let paletteLab = precomputePaletteLab([
            BeadColor(id: "R", name: "红", rgb: RGBColor(220, 30, 50), symbol: "R", brand: "MARD"),
            BeadColor(id: "G", name: "绿", rgb: RGBColor(30, 200, 80), symbol: "G", brand: "MARD"),
        ])
        // 查一个接近红的颜色，应命中 index 0。
        let result = findNearestBeadColorRgb(210, 40, 60, paletteLab: paletteLab)
        XCTAssertEqual(result.index, 0)
    }
}
