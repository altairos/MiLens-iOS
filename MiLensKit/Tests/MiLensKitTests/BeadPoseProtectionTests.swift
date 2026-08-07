import XCTest
@testable import MiLensKit

/// BeadPoseProtection 测试。翻译自源端 shared/.../test/BeadPoseProtection.test.ets。
final class BeadPoseProtectionTests: XCTestCase {

    private func poseSubject(_ confidence: Double = 1) -> BeadSubjectContext {
        return BeadSubjectContext(
            bbox: CropRect(x: 0, y: 0, width: 10, height: 10),
            pose: BeadPoseData(keypoints: [
                BeadPoseKeypoint(x: 0.5, y: 0.5, confidence: confidence),
                BeadPoseKeypoint(x: 0.2, y: 0.2, confidence: confidence),
                BeadPoseKeypoint(x: 0.8, y: 0.2, confidence: confidence),
                BeadPoseKeypoint(x: 0.2, y: 0.8, confidence: confidence),
                BeadPoseKeypoint(x: 0.8, y: 0.8, confidence: confidence),
            ])
        )
    }

    func testReturnsFifteenZerosWhenPoseDataUnavailable() {
        let result = flattenPoseKeypoints()
        XCTAssertEqual(result.count, 15)
        XCTAssertEqual(result[0], 0)
        XCTAssertEqual(result[14], 0)
    }

    func testFlattensFirstFiveKeypointsInStableXyzOrder() {
        let result = flattenPoseKeypoints(poseSubject(0.75))
        XCTAssertEqual(result[0], 0.5)
        XCTAssertEqual(result[1], 0.5)
        XCTAssertEqual(result[2], 0.75)
        XCTAssertEqual(Double(result[12]), 0.8, accuracy: 0.001)
        XCTAssertEqual(Double(result[13]), 0.8, accuracy: 0.001)
        XCTAssertEqual(result[14], 0.75)
    }

    func testMarksConfFacialLandmarksButPreservesEmptyCells() {
        var mask = [UInt8](repeating: 0, count: 25)
        var empty = [UInt8](repeating: 0, count: 25)
        empty[12] = 1
        applyPoseProtection(&mask, empty, gridW: 5, gridH: 5,
                            crop: CropArea(x: 0, y: 0, w: 10, h: 10), srcW: 10, srcH: 10,
                            subject: poseSubject())
        // empty[12]=1 → 格 12 不被标记
        XCTAssertEqual(mask[12], 0)
        // 格 13/19 应被标记（关键点附近）
        XCTAssertEqual(mask[13], 1)
        XCTAssertEqual(mask[19], 1)
    }

    func testIgnoresLowConfidenceLandmarksAndInvalidCrops() {
        var low = [UInt8](repeating: 0, count: 25)
        applyPoseProtection(&low, [UInt8](repeating: 0, count: 25), gridW: 5, gridH: 5,
                            crop: CropArea(x: 0, y: 0, w: 10, h: 10), srcW: 10, srcH: 10,
                            subject: poseSubject(0.49))
        XCTAssertFalse(low.contains(1))  // 低置信度不标记

        var invalid = [UInt8](repeating: 0, count: 25)
        applyPoseProtection(&invalid, [UInt8](repeating: 0, count: 25), gridW: 5, gridH: 5,
                            crop: CropArea(x: 0, y: 0, w: 0, h: 10), srcW: 10, srcH: 10,
                            subject: poseSubject())
        XCTAssertFalse(invalid.contains(1))  // 无效 crop 不标记
    }
}
