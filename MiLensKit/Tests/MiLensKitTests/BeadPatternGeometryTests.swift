import XCTest
@testable import MiLensKit

/// BeadPatternGeometry 测试。翻译自源端 shared/.../test/BeadPatternGeometry.test.ets。
/// 精确值断言守护 floor/ceil 语义与源端一致。
final class BeadPatternGeometryTests: XCTestCase {

    private func subject(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> BeadSubjectContext {
        return BeadSubjectContext(bbox: CropRect(x: x, y: y, width: width, height: height))
    }

    func testKeepsCompleteImageInFreeAndUnknownModes() {
        let free = computePatternCrop(srcW: 120, srcH: 80, mode: "free")
        let unknown = computePatternCrop(srcW: 120, srcH: 80, mode: "unknown")
        XCTAssertEqual(free.x, 0)
        XCTAssertEqual(free.y, 0)
        XCTAssertEqual(free.w, 120)
        XCTAssertEqual(free.h, 80)
        XCTAssertEqual(unknown.w, 120)
        XCTAssertEqual(unknown.h, 80)
    }

    func testUsesCenteredSquareWhenNoValidSubject() {
        let crop = computePatternCrop(srcW: 120, srcH: 80, mode: "portrait")
        XCTAssertEqual(crop.x, 20)
        XCTAssertEqual(crop.y, 0)
        XCTAssertEqual(crop.w, 80)
        XCTAssertEqual(crop.h, 80)
    }

    func testUsesModeSpecificPaddingAndClampsSubjectCrops() {
        let pet = subject(84, 54, 20, 20)
        let tight = computePatternCrop(srcW: 100, srcH: 80, mode: "tight_face", subject: pet)
        let full = computePatternCrop(srcW: 100, srcH: 80, mode: "fullBody", subject: pet)
        XCTAssertEqual(tight.w, 23)
        XCTAssertEqual(tight.x, 77)
        XCTAssertEqual(tight.y, 52)
        XCTAssertEqual(full.w, 32)
        XCTAssertEqual(full.x, 68)
        XCTAssertEqual(full.y, 48)
    }

    func testMapsFaceBoundsIntoGridAndRejectsInvalidInput() {
        let pet = subject(20, 10, 40, 40)
        let roi = computeFaceRoi(crop: CropArea(x: 0, y: 0, w: 100, h: 100), gridW: 50, gridH: 50, mode: "portrait", subject: pet)
        XCTAssertEqual(roi?.x, 13)
        XCTAssertEqual(roi?.y, 5)
        XCTAssertEqual(roi?.w, 14)
        XCTAssertEqual(roi?.h, 10)
        // 无效输入返回 nil
        XCTAssertNil(computeFaceRoi(crop: CropArea(x: 0, y: 0, w: 0, h: 100), gridW: 50, gridH: 50, mode: "portrait", subject: pet))
        XCTAssertNil(computeFaceRoi(crop: CropArea(x: 0, y: 0, w: 100, h: 100), gridW: 50, gridH: 50, mode: "portrait"))
    }

    func testMarksOnlyCellsOutsideCircularBadgeAsEmpty() {
        var empty = [UInt8](repeating: 0, count: 25)
        empty[12] = 7
        applyBadgeMask(&empty, w: 5, h: 5)
        XCTAssertEqual(empty[0], 1)
        XCTAssertEqual(empty[4], 1)
        XCTAssertEqual(empty[20], 1)
        XCTAssertEqual(empty[24], 1)
        XCTAssertEqual(empty[2], 0)
        XCTAssertEqual(empty[12], 7)  // 中心点不被覆盖
    }
}
