import XCTest
@testable import MiLensKit

/// DraftFeatureProtector 测试。翻译自源端 shared/.../test/DraftFeatureProtector.test.ets（3 用例）。
/// iOS `protectAndCleanup` 返回新副本（源端 in-place），故断言返回值而非原数组。
final class DraftFeatureProtectorTests: XCTestCase {

    func testReplacesAnIsolatedSubjectPixelWithNeighborMode() {
        // 3×3 grid，中心格为孤立色 2，周围全为 1
        let indices: [UInt8] = [1, 1, 1, 1, 2, 1, 1, 1, 1]
        let subject: [UInt8] = [1, 1, 1, 1, 1, 1, 1, 1, 1]
        let result = protectAndCleanup(
            indices, width: 3, height: 3,
            featureMask: nil, subjectMask: subject,
            preserveFace: false, preservePattern: false)
        XCTAssertEqual(result[4], 1)
    }

    func testPreservesAnIsolatedPixelAtConfidentFacialKeypoint() {
        // 同样的孤点布局，但 pose 关键点在中心 (0.5, 0.5) conf 0.9 → 豁免
        let indices: [UInt8] = [1, 1, 1, 1, 2, 1, 1, 1, 1]
        let subject: [UInt8] = [1, 1, 1, 1, 1, 1, 1, 1, 1]
        let pose = BeadPoseData(keypoints: [BeadPoseKeypoint(x: 0.5, y: 0.5, confidence: 0.9)])
        let result = protectAndCleanup(
            indices, width: 3, height: 3,
            featureMask: nil, subjectMask: subject,
            preserveFace: false, preservePattern: false, pose: pose)
        XCTAssertEqual(result[4], 2)
    }

    func testEstimatesFeaturesOnlyInsideBothBboxAndSubjectMask() {
        // 10×10 全主体 mask，第 23 格挖空
        var subject = [UInt8](repeating: 1, count: 100)
        subject[23] = 0
        let bbox = CropRect(x: 0, y: 0, width: 10, height: 10)
        let feature = estimateFeatureMask(mask: subject, width: 10, height: 10, bbox: bbox)
        // 格 22 在 mask 内且在 bbox 内 → 1
        XCTAssertEqual(feature[22], 1)
        // 格 23 被 mask 挖空 → 0
        XCTAssertEqual(feature[23], 0)
        // 格 0 在 bbox 左上角，但在五官估计区域上部 15% 之外 → 0
        XCTAssertEqual(feature[0], 0)
        // 格 99 在底部 → 0
        XCTAssertEqual(feature[99], 0)
    }
}
