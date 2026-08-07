import XCTest
@testable import MiLensKit

/// VirtualPaletteBuilder 测试。翻译自源端 shared/.../test/VirtualPalette.test.ets。
final class VirtualPaletteTests: XCTestCase {

    private func virtualColor(_ id: String, _ L: Double, _ a: Double, _ b: Double) -> VirtualColor {
        return VirtualColor(id: id, rgb: [0, 0, 0], lab: [L, a, b])
    }

    // MARK: - 源端用例翻译

    func testReturnsNeutralFallbackForFullyTransparentImage() {
        let palette = buildVirtualPalette(rgba: [1, 2, 3, 0], width: 1, height: 1, count: 8)
        XCTAssertEqual(palette.count, 1)
        XCTAssertEqual(palette[0].id, "vc_0")
        XCTAssertEqual(palette[0].lab[0], 50)
    }

    func testIsDeterministicAndClampsPaletteCountTo24() {
        let rgba: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 255, 255,
        ]
        let first = buildVirtualPalette(rgba: rgba, width: 2, height: 2, count: 99, seed: 17)
        let second = buildVirtualPalette(rgba: rgba, width: 2, height: 2, count: 99, seed: 17)
        XCTAssertLessThanOrEqual(first.count, 24)
        XCTAssertEqual(first.count, second.count)
        XCTAssertEqual(first[0].rgb, second[0].rgb)
    }

    func testMergesNearbyGraysButPreservesChromaticColors() {
        let palette = [
            virtualColor("g1", 50, 1, 1),
            virtualColor("g2", 55, 2, 1),
            virtualColor("red", 50, 40, 30),
        ]
        let result = mergeGrayVirtualColors(palette)
        XCTAssertEqual(result.palette.count, 2)
        XCTAssertEqual(result.remap[0], result.remap[1])
        XCTAssertNotEqual(result.remap[2], result.remap[0])
    }

    func testMarksTransparentPixelsAsEmptyDuringMapping() {
        let rgba: [UInt8] = [0, 0, 0, 0, 255, 255, 255, 255]
        let palette = [virtualColor("black", 0, 0, 0), virtualColor("white", 100, 0, 0)]
        let indices = mapPixelsToVirtualPalette(rgba: rgba, width: 2, height: 1, palette: palette)
        XCTAssertEqual(indices[0], 255)
        XCTAssertEqual(indices[1], 1)
    }

    func testUsesPoseKeypointsToKeepDarkFacialPixelsOnDarkerColor() {
        let rgba: [UInt8] = [66, 66, 66, 255]
        let palette = [virtualColor("dark", 20, 0, 0), virtualColor("mid", 30, 0, 0)]
        let withoutPose = mapPixelsToVirtualPalette(rgba: rgba, width: 1, height: 1, palette: palette)
        let withPose = mapPixelsToVirtualPalette(
            rgba: rgba, width: 1, height: 1, palette: palette,
            pose: BeadPoseData(keypoints: [BeadPoseKeypoint(x: 0, y: 0, confidence: 0.9)]))
        XCTAssertEqual(withoutPose[0], 1)
        XCTAssertEqual(withPose[0], 0)
    }

    func testAcceptsSoftMasksWithoutDroppingSubjectEdge() {
        let rgba: [UInt8] = [120, 120, 120, 255, 255, 0, 0, 255]
        let result = buildVirtualPalette(rgba: rgba, width: 2, height: 1, count: 4, mask: [0, 128])
        XCTAssertGreaterThan(result.count, 0)
        var hasChromatic = false
        for color in result {
            let chroma = (color.lab[1] * color.lab[1] + color.lab[2] * color.lab[2]).squareRoot()
            if chroma > 10 { hasChromatic = true }
        }
        XCTAssertTrue(hasChromatic)
    }
}
