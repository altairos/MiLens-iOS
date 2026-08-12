//  AvatarCropMathTests —— 头像裁切纯逻辑测试。
//  对应源端 AvatarCropPage.ets 的 clampOffset / doCrop 坐标转换行为规格。

import XCTest
@testable import MiLensKit

final class AvatarCropMathTests: XCTestCase {

    // MARK: - clampOffset

    func testClampOffsetZeroOffsetAtScale1() {
        // scale=1.0 时可移动范围 = containerSize/2 - circleRatio*containerSize/2
        // = 300/2 - 0.83*300/2 = 150 - 124.5 = 25.5
        let result = AvatarCropMath.clampOffset(
            offset: AvatarCropOffset(x: 0, y: 0), scale: 1.0, containerSize: 300)
        XCTAssertEqual(result.x, 0, accuracy: 0.01)
        XCTAssertEqual(result.y, 0, accuracy: 0.01)
    }

    func testClampOffsetWithinRange() {
        // 偏移在可移动范围内（10 < 25.5），保持不变
        let result = AvatarCropMath.clampOffset(
            offset: AvatarCropOffset(x: 10, y: -5), scale: 1.0, containerSize: 300)
        XCTAssertEqual(result.x, 10, accuracy: 0.01)
        XCTAssertEqual(result.y, -5, accuracy: 0.01)
    }

    func testClampOffsetBeyondRange() {
        // 偏移超出范围（100 > 25.5），钳制到 25.5
        let result = AvatarCropMath.clampOffset(
            offset: AvatarCropOffset(x: 100, y: -100), scale: 1.0, containerSize: 300)
        let maxRange = 300.0 / 2 - 0.83 * 300 / 2  // 25.5
        XCTAssertEqual(result.x, maxRange, accuracy: 0.01)
        XCTAssertEqual(result.y, -maxRange, accuracy: 0.01)
    }

    func testClampOffsetScale2IncreasesRange() {
        // scale=2.0 时可移动范围 = 2*300/2 - 0.83*300/2 = 300 - 124.5 = 175.5
        let result = AvatarCropMath.clampOffset(
            offset: AvatarCropOffset(x: 100, y: 0), scale: 2.0, containerSize: 300)
        XCTAssertEqual(result.x, 100, accuracy: 0.01)  // 100 < 175.5，不钳制
    }

    func testClampOffsetZeroScaleReturnsZero() {
        let result = AvatarCropMath.clampOffset(
            offset: AvatarCropOffset(x: 50, y: 50), scale: 0, containerSize: 300)
        XCTAssertEqual(result.x, 0)
        XCTAssertEqual(result.y, 0)
    }

    // MARK: - computeCropRect

    func testComputeCropRectCenterDefault() {
        // 默认状态（无偏移、scale=1.0）：裁剪区域应在图片中心
        let rect = AvatarCropMath.computeCropRect(
            imageSize: AvatarCropSize(width: 1000, height: 800),
            containerSize: 300,
            scale: 1.0,
            offset: AvatarCropOffset(x: 0, y: 0)
        )
        // 裁剪直径 = 0.83 * 300 / 1.0 * (1000/300) = 830（X方向）
        // 裁剪直径 = 0.83 * 300 / 1.0 * (800/300) = 664（Y方向），取 min = 664
        XCTAssertEqual(rect.width, 664, accuracy: 1)
        // 中心裁剪：x = (1000 - 664) / 2 = 168
        XCTAssertEqual(rect.originX, 168, accuracy: 1)
    }

    func testComputeCropRectScale2SmallerCrop() {
        // scale=2.0：裁剪区域是 scale=1 的一半
        let rect1 = AvatarCropMath.computeCropRect(
            imageSize: AvatarCropSize(width: 1000, height: 1000),
            containerSize: 300, scale: 1.0, offset: AvatarCropOffset(x: 0, y: 0))
        let rect2 = AvatarCropMath.computeCropRect(
            imageSize: AvatarCropSize(width: 1000, height: 1000),
            containerSize: 300, scale: 2.0, offset: AvatarCropOffset(x: 0, y: 0))
        XCTAssertEqual(rect2.width, rect1.width / 2, accuracy: 1)
    }

    func testComputeCropRectOffsetShiftsCenter() {
        // 正偏移将裁剪中心向左上移（srcCenter = imgCenter - offset * ppVp / scale）
        let noOffset = AvatarCropMath.computeCropRect(
            imageSize: AvatarCropSize(width: 1000, height: 1000),
            containerSize: 300, scale: 1.0, offset: AvatarCropOffset(x: 0, y: 0))
        let withOffset = AvatarCropMath.computeCropRect(
            imageSize: AvatarCropSize(width: 1000, height: 1000),
            containerSize: 300, scale: 1.0,
            offset: AvatarCropOffset(x: 50, y: 0))
        // X 方向：裁剪中心左移 → originX 减小
        XCTAssertLessThan(withOffset.originX, noOffset.originX)
    }

    func testComputeCropRectBoundaryClamp() {
        // 极端偏移不应让裁剪框超出图片边界
        let rect = AvatarCropMath.computeCropRect(
            imageSize: AvatarCropSize(width: 500, height: 500),
            containerSize: 300, scale: 1.0,
            offset: AvatarCropOffset(x: 1000, y: 1000))
        XCTAssertGreaterThanOrEqual(rect.originX, 0)
        XCTAssertGreaterThanOrEqual(rect.originY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 500)
        XCTAssertLessThanOrEqual(rect.maxY, 500)
    }

    func testComputeCropRectZeroImageFallback() {
        // 图片尺寸为 0 时回退到安全默认（零矩形）
        let rect = AvatarCropMath.computeCropRect(
            imageSize: AvatarCropSize(width: 0, height: 0),
            containerSize: 300, scale: 1.0, offset: AvatarCropOffset(x: 0, y: 0))
        XCTAssertEqual(rect.width, 0)
        XCTAssertEqual(rect.height, 0)
    }

    func testComputeCropRectSquareImage() {
        // 正方形图片 + 正方形容器 + 无偏移：裁剪框居中
        let rect = AvatarCropMath.computeCropRect(
            imageSize: AvatarCropSize(width: 800, height: 800),
            containerSize: 300, scale: 1.0, offset: AvatarCropOffset(x: 0, y: 0))
        // 直径 = 0.83 * 300 * (800/300) / 1 = 664
        XCTAssertEqual(rect.width, 664, accuracy: 1)
        XCTAssertEqual(rect.height, 664, accuracy: 1)
        XCTAssertEqual(rect.originX, (800 - 664) / 2, accuracy: 1)
        XCTAssertEqual(rect.originY, (800 - 664) / 2, accuracy: 1)
    }
}
