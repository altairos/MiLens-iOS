import XCTest
@testable import MiLensKit

/// DraftToBeadMapper 测试。翻译自源端 shared/.../test/DraftToBeadMapper.test.ets。
final class DraftToBeadMapperTests: XCTestCase {

    private func color(_ id: String, _ r: Int, _ g: Int, _ b: Int, tags: [BeadColorTag]? = nil) -> BeadColor {
        return BeadColor(id: id, name: id, rgb: RGBColor(r, g, b), symbol: id, brand: "", tags: tags)
    }

    private func virtualColor(_ id: String, _ r: Int, _ g: Int, _ b: Int) -> VirtualColor {
        let lab = rgbToLab(Double(r), Double(g), Double(b))
        return VirtualColor(id: id, rgb: [r, g, b], lab: [lab.L, lab.a, lab.b])
    }

    private func makeDraft(_ width: Int, _ height: Int, _ indices: [UInt8], _ virtualPalette: [VirtualColor]) -> StylizedDraftResult {
        let diag = DraftDiagnostics(usedVirtualColorCount: virtualPalette.count,
                                    subjectCoverageRatio: 1, featurePreserveScore: 1,
                                    colorBlockCleanliness: 1)
        return StylizedDraftResult(width: width, height: height, indices: indices,
                                   virtualPalette: virtualPalette, diagnostics: diag)
    }

    func testMapsEachVirtualColorToNearestMardColorWhenBeadColorsOmitted() {
        let d = makeDraft(2, 1, [0, 1], [
            virtualColor("v_red", 255, 0, 0),
            virtualColor("v_blue", 0, 0, 255),
        ])
        let palette = [color("m_red", 255, 0, 0), color("m_blue", 0, 0, 255)]
        let beadIndices = mapDraftToBeadPalette(d, paletteLab: precomputePaletteLab(palette), petPenalty: 0)
        XCTAssertEqual(beadIndices.count, 2)
        XCTAssertEqual(beadIndices[0], 0)
        XCTAssertEqual(beadIndices[1], 1)
    }

    func testEncodesVirtualIndex255AsEmptyMarker65535() {
        let d = makeDraft(2, 1, [0, 255], [virtualColor("v_red", 255, 0, 0)])
        let palette = [color("m_red", 255, 0, 0)]
        let beadIndices = mapDraftToBeadPalette(d, paletteLab: precomputePaletteLab(palette), petPenalty: 0)
        XCTAssertEqual(beadIndices[0], 0)
        XCTAssertEqual(beadIndices[1], 65535)
    }

    func testAppliesRoleAffinityDiscountWhenBeadColorsSupplyMatchingTag() {
        let d = makeDraft(1, 1, [0], [virtualColor("v0", 230, 140, 60)])
        let palette = [
            color("untagged", 200, 100, 30),
            color("orange", 200, 100, 30, tags: [.orangeFur]),
        ]
        let paletteLab = precomputePaletteLab(palette)
        // 无 beadColors → 第一个色胜（strict <）
        let withoutAffinity = mapDraftToBeadPalette(d, paletteLab: paletteLab, petPenalty: 0)
        XCTAssertEqual(withoutAffinity[0], 0)
        // 有 beadColors + orange_fur 标签 → 15% 折扣翻转胜者
        let withAffinity = mapDraftToBeadPalette(d, paletteLab: paletteLab, petPenalty: 0, beadColors: palette)
        XCTAssertEqual(withAffinity[0], 1)
    }

    func testSkipsAffinityDiscountWhenTagsOutsideRoleAffinityList() {
        let d = makeDraft(1, 1, [0], [virtualColor("v0", 255, 0, 0)])
        let palette = [
            color("red", 255, 0, 0, tags: [.blueTint]),
            color("blue", 0, 0, 255, tags: [.blueTint]),
        ]
        let beadIndices = mapDraftToBeadPalette(d, paletteLab: precomputePaletteLab(palette), petPenalty: 0, beadColors: palette)
        XCTAssertEqual(beadIndices[0], 0)
    }

    func testMapsOutOfRangeVirtualIndicesToEmptyMarker() {
        let d = makeDraft(1, 1, [5], [virtualColor("v0", 255, 0, 0)])
        let palette = [color("m_red", 255, 0, 0)]
        let beadIndices = mapDraftToBeadPalette(d, paletteLab: precomputePaletteLab(palette), petPenalty: 0)
        XCTAssertEqual(beadIndices[0], 65535)
    }

    func testPreservesWidthTimesHeightLayoutFor2x2Grid() {
        let d = makeDraft(2, 2, [0, 1, 1, 0], [
            virtualColor("v_red", 255, 0, 0),
            virtualColor("v_blue", 0, 0, 255),
        ])
        let palette = [color("m_red", 255, 0, 0), color("m_blue", 0, 0, 255)]
        let beadIndices = mapDraftToBeadPalette(d, paletteLab: precomputePaletteLab(palette), petPenalty: 0)
        XCTAssertEqual(beadIndices.count, 4)
        XCTAssertEqual(beadIndices[0], 0)
        XCTAssertEqual(beadIndices[1], 1)
        XCTAssertEqual(beadIndices[2], 1)
        XCTAssertEqual(beadIndices[3], 0)
    }
}
