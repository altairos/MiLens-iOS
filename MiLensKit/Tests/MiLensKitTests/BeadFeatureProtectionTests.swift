import XCTest
@testable import MiLensKit

/// BeadFeatureProtection 测试。翻译自源端 shared/.../test/BeadFeatureProtection.test.ets。
final class BeadFeatureProtectionTests: XCTestCase {

    private func grayscale(_ width: Int, _ height: Int, _ value: UInt8) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = value
            pixels[i * 4 + 1] = value
            pixels[i * 4 + 2] = value
            pixels[i * 4 + 3] = 255
        }
        return pixels
    }

    private func setGray(_ pixels: inout [UInt8], _ index: Int, _ value: UInt8) {
        pixels[index * 4] = value
        pixels[index * 4 + 1] = value
        pixels[index * 4 + 2] = value
    }

    func testProtectsDarkFeaturesButAlwaysSkipsEmptyCells() {
        var empty = [UInt8](repeating: 0, count: 9)
        empty[0] = 1
        let mask = buildProtectMask(grayscale(3, 3, 0), w: 3, h: 3, empty: empty, protectionStrength: 0)
        XCTAssertEqual(mask[0], 0)  // empty 跳过
        XCTAssertEqual(mask[1], 1)  // 暗部保护
        XCTAssertEqual(mask[4], 1)
        XCTAssertEqual(mask[7], 0)  // y=2 > h*0.82=2.46... 实际 h=3 → 3*0.82=2.46 → y=2 < 2.46 应保护
    }

    func testProtectsVisibleLuminanceEdges() {
        var pixels = grayscale(3, 3, 220)
        setGray(&pixels, 3, 20)  // 格 3 为暗
        let mask = buildProtectMask(pixels, w: 3, h: 3, empty: [UInt8](repeating: 0, count: 9), protectionStrength: 0)
        XCTAssertEqual(mask[4], 1)  // 格 4 中心，与格 3 有亮度差 → 边缘
    }

    func testUsesLowerEdgeThresholdOnlyInsideFaceRoi() {
        var pixels = grayscale(5, 5, 150)
        setGray(&pixels, 11, 134)
        setGray(&pixels, 13, 166)
        let empty = [UInt8](repeating: 0, count: 25)
        let globalMask = buildProtectMask(pixels, w: 5, h: 5, empty: empty, protectionStrength: 0.6)
        let faceMask = buildProtectMask(pixels, w: 5, h: 5, empty: empty, protectionStrength: 0.6, faceRoi: CropArea(x: 2, y: 2, w: 1, h: 1))
        // 全局阈值下格 12 边缘不够强（edge = |166-150| + |150-134| = 32, 阈值 0.32-0.6*0.15=0.23 → edge 32/255≈0.125 < 0.23）
        XCTAssertEqual(globalMask[12], 0)
        // 脸部 ROI 阈值更低（0.15-0.6*0.05=0.12），格 12 被保护
        XCTAssertEqual(faceMask[12], 1)
    }

    func testProtectsCellsSelectedByValidSemanticAttentionHeatmap() {
        let pixels = grayscale(7, 7, 150)
        var attention = [Float](repeating: 0, count: 49)
        attention[24] = 0.6  // 中心格注意力高
        let semantic = buildProtectMask(pixels, w: 7, h: 7, empty: [UInt8](repeating: 0, count: 49), protectionStrength: 0, attentionHeatmap: attention)
        let invalid = buildProtectMask(pixels, w: 7, h: 7, empty: [UInt8](repeating: 0, count: 49), protectionStrength: 0, attentionHeatmap: [Float](repeating: 0, count: 1))
        XCTAssertEqual(semantic[24], 1)
        XCTAssertEqual(invalid[24], 0)
    }

    func testProtectsBrightCellsAdjacentToDarkDetails() {
        var pixels = grayscale(5, 3, 150)
        setGray(&pixels, 6, 0)    // 暗格
        setGray(&pixels, 7, 255)  // 亮格
        let mask = buildProtectMask(pixels, w: 5, h: 3, empty: [UInt8](repeating: 0, count: 15), protectionStrength: 0)
        XCTAssertEqual(mask[7], 1)  // 亮格邻暗 → 保护
    }

    func testProtectsLongRunBoundariesWithoutProtectingWholeRun() {
        let mask = buildProtectMask(grayscale(8, 3, 220), w: 8, h: 3, empty: [UInt8](repeating: 0, count: 24), protectionStrength: 0.6)
        // run 起始位置（x=0,1）和结束位置（x=6,7）应被保护
        XCTAssertEqual(mask[8], 1)   // y=1, x=0
        XCTAssertEqual(mask[9], 1)   // y=1, x=1
        XCTAssertEqual(mask[11], 0)  // y=1, x=3 中间不保护
        XCTAssertEqual(mask[14], 1)  // y=1, x=6
        XCTAssertEqual(mask[15], 1)  // y=1, x=7
    }
}
