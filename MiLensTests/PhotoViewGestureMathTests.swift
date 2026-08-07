import XCTest
@testable import MiLens

/// PhotoViewGestureMath 测试（对应源端 PhotoViewGestureMath.test.ets）。
/// 覆盖裁剪偏移 / 平移偏移 / 缩放钳制 / 旋转宽高比 / 窗口重载判定。
final class PhotoViewGestureMathTests: XCTestCase {

    // MARK: - computeMaxCropOffset

    func testComputeMaxCropOffsetReturnsZeroForZeroContainerWidth() {
        XCTAssertEqual(PhotoViewGestureMath.computeMaxCropOffset(containerWidth: 0, photoAspectRatio: 1.5), 0, accuracy: 1e-9)
    }

    func testComputeMaxCropOffsetReturnsPositiveWhenPhotoWiderThanContainer() {
        // photoAR=1.5 (3:2), containerAR=0.75 (3:4)
        // maxOff = 300 * (1.5 - 0.75) / (2 * 0.75) = 300 * 0.75 / 1.5 = 150
        XCTAssertEqual(PhotoViewGestureMath.computeMaxCropOffset(containerWidth: 300, photoAspectRatio: 1.5), 150, accuracy: 1e-9)
    }

    func testComputeMaxCropOffsetReturnsZeroWhenPhotoNarrowerThanContainer() {
        XCTAssertEqual(PhotoViewGestureMath.computeMaxCropOffset(containerWidth: 300, photoAspectRatio: 0.5), 0, accuracy: 1e-9)
    }

    // MARK: - computeMaxPanOffset

    func testComputeMaxPanOffsetReturnsZeroForZeroContainerWidth() {
        XCTAssertEqual(PhotoViewGestureMath.computeMaxPanOffset(containerWidth: 0, imageScale: 2), 0, accuracy: 1e-9)
    }

    func testComputeMaxPanOffsetReturnsZeroWhenScaleLEOne() {
        XCTAssertEqual(PhotoViewGestureMath.computeMaxPanOffset(containerWidth: 300, imageScale: 1), 0, accuracy: 1e-9)
    }

    func testComputeMaxPanOffsetReturnsPositiveForScaleGreaterThanOne() {
        // 300 * (2 - 1) / 2 = 150
        XCTAssertEqual(PhotoViewGestureMath.computeMaxPanOffset(containerWidth: 300, imageScale: 2), 150, accuracy: 1e-9)
    }

    // MARK: - clampScale

    func testClampScaleClampsToMin() {
        XCTAssertEqual(PhotoViewGestureMath.clampScale(0.3), 0.5, accuracy: 1e-9)
    }

    func testClampScaleClampsToMax() {
        XCTAssertEqual(PhotoViewGestureMath.clampScale(10), 5, accuracy: 1e-9)
    }

    func testClampScaleReturnsValueWithinRange() {
        XCTAssertEqual(PhotoViewGestureMath.clampScale(2.5), 2.5, accuracy: 1e-9)
    }

    // MARK: - clampPanOffset

    func testClampPanOffsetClampsToMaxPan() {
        XCTAssertEqual(PhotoViewGestureMath.clampPanOffset(100, maxPan: 50), 50, accuracy: 1e-9)
        XCTAssertEqual(PhotoViewGestureMath.clampPanOffset(-100, maxPan: 50), -50, accuracy: 1e-9)
    }

    func testClampPanOffsetReturnsZeroWhenMaxPanLEZero() {
        XCTAssertEqual(PhotoViewGestureMath.clampPanOffset(50, maxPan: 0), 0, accuracy: 1e-9)
    }

    // MARK: - computeRotatedAspectRatio

    func testComputeRotatedAspectRatioReturnsWidthOverHeightAtZeroDegrees() {
        let result = PhotoViewGestureMath.computeRotatedAspectRatio(width: 800, height: 600, rotation: 0)
        XCTAssertEqual(result, 800.0 / 600.0, accuracy: 1e-9)
    }

    func testComputeRotatedAspectRatioSwapsDimensionsAtNinetyDegrees() {
        let result = PhotoViewGestureMath.computeRotatedAspectRatio(width: 800, height: 600, rotation: 90)
        XCTAssertEqual(result, 600.0 / 800.0, accuracy: 1e-9)
    }

    func testComputeRotatedAspectRatioSwapsDimensionsAtTwoHundredSeventyDegrees() {
        let result = PhotoViewGestureMath.computeRotatedAspectRatio(width: 800, height: 600, rotation: 270)
        XCTAssertEqual(result, 600.0 / 800.0, accuracy: 1e-9)
    }

    func testComputeRotatedAspectRatioReturnsFallbackFourOverThreeForInvalidDimsAtZero() {
        let result = PhotoViewGestureMath.computeRotatedAspectRatio(width: 0, height: 0, rotation: 0)
        XCTAssertEqual(result, 4.0 / 3.0, accuracy: 1e-9)
    }

    func testComputeRotatedAspectRatioReturnsFallbackThreeOverFourForInvalidDimsAtNinety() {
        let result = PhotoViewGestureMath.computeRotatedAspectRatio(width: 0, height: 0, rotation: 90)
        XCTAssertEqual(result, 3.0 / 4.0, accuracy: 1e-9)
    }

    // MARK: - shouldReloadWindow

    func testShouldReloadWindowReturnsTrueWhenNextIndexGoesBelowZero() {
        XCTAssertTrue(PhotoViewGestureMath.shouldReloadWindow(currentIndex: 0, windowLength: 21, offset: -1))
    }

    func testShouldReloadWindowReturnsTrueWhenNextIndexExceedsLength() {
        XCTAssertTrue(PhotoViewGestureMath.shouldReloadWindow(currentIndex: 20, windowLength: 21, offset: 1))
    }

    func testShouldReloadWindowReturnsFalseWhenNextIndexIsWithinWindow() {
        XCTAssertFalse(PhotoViewGestureMath.shouldReloadWindow(currentIndex: 5, windowLength: 21, offset: 1))
    }
}
