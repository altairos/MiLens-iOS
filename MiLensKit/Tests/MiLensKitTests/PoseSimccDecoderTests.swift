import XCTest
@testable import MiLensKit

/// PoseSimccDecoder 测试。翻译自源端 entry/src/test/PoseInferenceMath.test.ets，
/// 数值断言与原用例保持一致；仅预处理通道序改为 iOS RGBA（源端 PixelMap 为 BGRA）。
final class PoseSimccDecoderTests: XCTestCase {

    private func cropRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CropRect {
        CropRect(x: x, y: y, width: w, height: h)
    }

    private func pose(keypoints: [(x: Double, y: Double, confidence: Double)]) -> BeadPoseData {
        BeadPoseData(keypoints: keypoints.map { BeadPoseKeypoint(x: $0.x, y: $0.y, confidence: $0.confidence) })
    }

    // MARK: - 预处理

    /// iOS 解码输出 RGBA，模型期望 RGB（通道序与源端 BGRA 相反）。
    func testPreprocessesRGBAAsModelRGB_NCHW() throws {
        let rgba: [UInt8] = [250, 20, 10, 255]  // R=250, G=20, B=10, A=255
        let result = try preparePoseInput(
            rgba: rgba, sourceWidth: 1, sourceHeight: 1,
            bbox: cropRect(0, 0, 1, 1), inputSize: 1, padding: 1)
        XCTAssertGreaterThan(result.data[0], result.data[2], "R 通道应高于 B 通道（RGBA→RGB）")
        XCTAssertEqual(result.data[0], Float((250.0 / 255 - 0.485) / 0.229), accuracy: 0.0001)
        XCTAssertEqual(result.data[2], Float((10.0 / 255 - 0.406) / 0.225), accuracy: 0.0001)
    }

    func testRejectsInvalidBufferAndCrop() {
        XCTAssertThrowsError(try preparePoseInput(
            rgba: [1, 2, 3], sourceWidth: 1, sourceHeight: 1,
            bbox: cropRect(0, 0, 1, 1), inputSize: 1))
        XCTAssertThrowsError(try preparePoseInput(
            rgba: [UInt8](repeating: 0, count: 4), sourceWidth: 1, sourceHeight: 1,
            bbox: cropRect(0, 0, 0, 1), inputSize: 1))
    }

    // MARK: - SimCC 解码

    /// 解码原始 SimCC 峰值并把裁框映射回源图坐标（源端同数值用例）。
    func testDecodesSimccPeaksAndMapsCropBackToSource() {
        let pair = PoseOutputPair(
            simccX: [0.01, 0.1, 2.0, 0.2],
            simccY: [0.01, 1.8, 0.2, 0.1])
        let transform = PoseTransform(
            sourceWidth: 100, sourceHeight: 100,
            cropX: 20, cropY: 10, cropSize: 40, inputSize: 2)
        let pose = decodePoseOutputs(
            pair: pair, transform: transform, keypointCount: 1,
            simccLength: 4, splitRatio: 2, scoreThreshold: 0.2)
        XCTAssertNotNil(pose)
        XCTAssertEqual(pose!.keypoints[0].x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(pose!.keypoints[0].y, 0.2, accuracy: 0.0001)
        // one-vs-rest softmax 近似: 1/(1+(N-1)·exp(-s)), N=4
        // confX=0.7112(s=2.0), confY=0.6685(s=1.8) -> sqrt=0.6895
        XCTAssertEqual(pose!.keypoints[0].confidence, 0.69, accuracy: 0.01)
    }

    /// 无原始峰值达到阈值时返回 nil（源端同用例）。
    func testReturnsNilWhenNoRawPeakReachesThreshold() {
        let pair = PoseOutputPair(
            simccX: [-3.0, -3.0],
            simccY: [-3.0, -3.0])
        let transform = PoseTransform(
            sourceWidth: 1, sourceHeight: 1,
            cropX: 0, cropY: 0, cropSize: 1, inputSize: 1)
        XCTAssertNil(decodePoseOutputs(
            pair: pair, transform: transform, keypointCount: 1,
            simccLength: 2, splitRatio: 2, scoreThreshold: 0.2))
    }

    /// 固定顺序契约：左眼、右眼、鼻子（前三点）决定锚点稳定性。
    func testHasStableFaceAnchorsRequiresFirstThreeKeypoints() {
        let stable = pose(keypoints: [
            (0.4, 0.3, 0.8), (0.6, 0.3, 0.82), (0.5, 0.5, 0.85)
        ])
        XCTAssertTrue(hasStableFaceAnchors(stable, scoreThreshold: 0.2))
        let unstable = pose(keypoints: [
            (0.4, 0.3, 0.8), (0.6, 0.3, 0.1), (0.5, 0.5, 0.85)
        ])
        XCTAssertFalse(hasStableFaceAnchors(unstable, scoreThreshold: 0.2))
    }

    // MARK: - 脸框细化

    /// 从稳定粗锚点推导更小的方形脸框（源端同用例）。
    func testDerivesSmallerSquareFaceBoxFromStableCoarseAnchors() {
        let p = pose(keypoints: [
            (0.40, 0.32, 0.8),
            (0.60, 0.32, 0.82),
            (0.50, 0.46, 0.85),
            (0.34, 0.20, 0.7),
            (0.66, 0.20, 0.72)
        ])
        let face = deriveFaceBoxFromPose(
            pose: p, sourceWidth: 1000, sourceHeight: 800,
            subjectBox: cropRect(100, 50, 800, 700), scoreThreshold: 0.2)
        XCTAssertNotNil(face)
        XCTAssertEqual(face!.width, face!.height)
        XCTAssertLessThan(face!.width, 700)
        XCTAssertTrue(face!.x < 400 && face!.x + face!.width > 600)
        XCTAssertTrue(face!.y < 160 && face!.y + face!.height > 368)
    }

    /// 双眼和鼻子缺失时跳过细化（源端同用例）。
    func testSkipsFaceRefinementWithoutBothEyesAndNose() {
        let p = pose(keypoints: [
            (0.4, 0.3, 0.8),
            (0.6, 0.3, 0.1),
            (0.5, 0.5, 0.8)
        ])
        XCTAssertFalse(hasStableFaceAnchors(p, scoreThreshold: 0.2))
        XCTAssertNil(deriveFaceBoxFromPose(
            pose: p, sourceWidth: 100, sourceHeight: 100,
            subjectBox: cropRect(0, 0, 100, 100), scoreThreshold: 0.2))
    }

    /// 粗锚点超出主体框容差时拒绝细化（源端同用例）。
    func testRejectsCoarseAnchorsOutsideSubjectBox() {
        let p = pose(keypoints: [
            (0.1, 0.1, 0.8),
            (0.5, 0.4, 0.8),
            (0.5, 0.5, 0.8)
        ])
        XCTAssertNil(deriveFaceBoxFromPose(
            pose: p, sourceWidth: 100, sourceHeight: 100,
            subjectBox: cropRect(30, 30, 40, 50), scoreThreshold: 0.2))
    }

    /// 脸框占比过大（≥ 主体框 90%）或过小（< 16px）时拒绝（源端守卫语义）。
    func testRejectsFaceBoxTooLargeOrTooSmallRelativeToSubject() {
        // 跨整图的关键点 → 外接框接近整图 → side >= subjectSide * 0.90
        let wide = pose(keypoints: [
            (0.05, 0.30, 0.9), (0.95, 0.30, 0.9), (0.50, 0.50, 0.9),
            (0.05, 0.20, 0.9), (0.95, 0.20, 0.9)
        ])
        XCTAssertNil(deriveFaceBoxFromPose(
            pose: wide, sourceWidth: 100, sourceHeight: 100,
            subjectBox: cropRect(0, 0, 100, 100), scoreThreshold: 0.2))
        // 极近关键点 → side < 16（spanX=2 → faceWidth=3；spanY=4 → faceHeight=6.8）
        let tiny = pose(keypoints: [
            (0.40, 0.40, 0.9), (0.42, 0.40, 0.9), (0.41, 0.42, 0.9),
            (0.40, 0.38, 0.9), (0.42, 0.38, 0.9)
        ])
        XCTAssertNil(deriveFaceBoxFromPose(
            pose: tiny, sourceWidth: 100, sourceHeight: 100,
            subjectBox: cropRect(10, 10, 80, 80), scoreThreshold: 0.2))
    }
}
