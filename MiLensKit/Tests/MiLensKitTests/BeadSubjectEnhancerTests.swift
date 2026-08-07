import XCTest
@testable import MiLensKit

/// BeadSubjectEnhancer 测试。翻译自源端 shared/.../test/BeadSubjectEnhancer.test.ets。
final class BeadSubjectEnhancerTests: XCTestCase {

    private func options(_ contrast: Double, _ desaturation: Double, _ blur: Double, size: Int = 58) -> SubjectEnhanceOptions {
        return SubjectEnhanceOptions(subjectLocalContrast: contrast, backgroundDesaturation: desaturation,
                                     backgroundBlurStrength: blur, targetWidth: size, targetHeight: size)
    }

    private func subject(_ mask: [UInt8]) -> BeadSubjectContext {
        return BeadSubjectContext(bbox: CropRect(x: 0, y: 0, width: 1, height: 1), mask: mask)
    }

    func testMapsOffsetCropUsingOriginalSourceRowStride() {
        var sourceMask = [UInt8](repeating: 0, count: 8)
        sourceMask[2] = 255
        sourceMask[7] = 128
        let mapped = mapSubjectMask(2, 2, CropArea(x: 2, y: 0, w: 2, h: 2), 4, 2, sourceMask)
        XCTAssertEqual(mapped[0], 255)  // crop.x=2, dst(0,0)→src(2,0)=idx2=255
        XCTAssertEqual(mapped[1], 0)
        XCTAssertEqual(mapped[2], 0)
        XCTAssertEqual(mapped[3], 128)  // dst(1,1)→src(3,1)=idx7=128
    }

    func testMapsSubjectMaskAndBboxIntoFinalDraftGrid() {
        var sourceMask = [UInt8](repeating: 0, count: 8)
        sourceMask[2] = 255; sourceMask[7] = 255
        var heatmap = [Float](repeating: 0, count: 49)
        for i in 0..<49 { heatmap[i] = Float(i) }
        let sourceSubject = BeadSubjectContext(
            bbox: CropRect(x: 2, y: 0, width: 2, height: 2),
            mask: sourceMask,
            attentionHeatmap: heatmap,
            pose: BeadPoseData(keypoints: [
                BeadPoseKeypoint(x: 0.75, y: 0.5, confidence: 0.9),
                BeadPoseKeypoint(x: 0.25, y: 0.5, confidence: 0.8),
            ])
        )
        let mapped = mapSubjectContextToGrid(2, 2, CropArea(x: 2, y: 0, w: 2, h: 2), 4, 2, sourceSubject)
        XCTAssertEqual(mapped.mask?[0], 255)
        XCTAssertEqual(mapped.mask?[3], 255)
        XCTAssertEqual(mapped.bbox.x, 0)
        XCTAssertEqual(mapped.bbox.y, 0)
        XCTAssertEqual(mapped.bbox.width, 2)
        XCTAssertEqual(mapped.bbox.height, 2)
        XCTAssertEqual(mapped.pose?.keypoints[0].x, 0.5)
        XCTAssertEqual(mapped.pose?.keypoints[0].confidence, 0.9)
        XCTAssertEqual(mapped.pose?.keypoints[1].x, 0)
        XCTAssertEqual(mapped.pose?.keypoints[1].confidence, 0)
        XCTAssertEqual(mapped.attentionHeatmap?[0], 3)
        XCTAssertEqual(mapped.attentionHeatmap?[48], 48)
    }

    func testDesaturatesOnlyBackgroundSelectedByOffsetSourceMask() {
        var sourceMask = [UInt8](repeating: 0, count: 8)
        sourceMask[2] = 255  // 主体在 src(2,0)
        var pixels: [UInt8] = [
            255, 0, 0, 255, 255, 0, 0, 255,
            255, 0, 0, 255, 255, 0, 0, 255,
        ]
        applySubjectAwareEnhancements(&pixels, width: 2, height: 2,
                                      crop: CropArea(x: 2, y: 0, w: 2, h: 2), srcW: 4, srcH: 2,
                                      subject: subject(sourceMask), options: options(0, 1, 0))
        // 格 0 (主体) 不变 → 红
        XCTAssertEqual(pixels[0], 255)
        XCTAssertEqual(pixels[1], 0)
        // 格 1 (背景) 被降饱和 → 灰
        XCTAssertEqual(pixels[4], 54)
        XCTAssertEqual(pixels[5], 54)
        XCTAssertEqual(pixels[6], 54)
    }

    func testBlursBackgroundWhileRetainingSubjectColorAndAlpha() {
        let mask: [UInt8] = [0, 0, 255, 0, 0]
        var pixels: [UInt8] = [
            0, 0, 0, 10, 0, 0, 0, 20, 255, 0, 0, 30,
            0, 0, 0, 40, 0, 0, 0, 50,
        ]
        applySubjectAwareEnhancements(&pixels, width: 5, height: 1,
                                      crop: CropArea(x: 0, y: 0, w: 5, h: 1), srcW: 5, srcH: 1,
                                      subject: subject(mask), options: options(0, 0, 1))
        // 格 0 (背景) 被模糊
        XCTAssertEqual(pixels[0], 85)   // 5×5 box blur 边界处理
        // 格 2 (主体) 不变
        XCTAssertEqual(pixels[8], 255)
        XCTAssertEqual(pixels[11], 30)  // alpha 不变
        XCTAssertEqual(pixels[3], 10)
    }

    func testScalesLocalContrastDownForSmallTargetGrids() {
        let mask = [UInt8](repeating: 255, count: 25)
        var large = [UInt8](repeating: 0, count: 100)
        var small = [UInt8](repeating: 0, count: 100)
        for i in 0..<25 {
            large[i * 4] = 100; large[i * 4 + 1] = 100; large[i * 4 + 2] = 100; large[i * 4 + 3] = 255
        }
        large[48] = 130; large[49] = 130; large[50] = 130
        small = large
        let crop = CropArea(x: 0, y: 0, w: 5, h: 5)
        applySubjectAwareEnhancements(&large, width: 5, height: 5, crop: crop, srcW: 5, srcH: 5,
                                      subject: subject(mask), options: options(1, 0, 0, size: 58))
        applySubjectAwareEnhancements(&small, width: 5, height: 5, crop: crop, srcW: 5, srcH: 5,
                                      subject: subject(mask), options: options(1, 0, 0, size: 29))
        // 大网格的对比增强更强 → 偏离更大
        XCTAssertGreaterThan(Int(large[48]), Int(small[48]))
        // 小网格仍有增强（scale > 0）
        XCTAssertGreaterThan(Int(small[48]), 130)
    }

    func testReturnsWithoutModifyingWhenEveryStrengthDisabled() {
        var pixels: [UInt8] = [10, 20, 30, 40]
        applySubjectAwareEnhancements(&pixels, width: 1, height: 1,
                                      crop: CropArea(x: 0, y: 0, w: 1, h: 1), srcW: 1, srcH: 1,
                                      subject: subject([255]), options: options(0, 0, 0))
        XCTAssertEqual(pixels[0], 10)
        XCTAssertEqual(pixels[1], 20)
        XCTAssertEqual(pixels[2], 30)
        XCTAssertEqual(pixels[3], 40)
    }
}
