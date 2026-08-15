import XCTest
@testable import MiLens

/// BeadPreviewLayoutLogic 测试（audit-6 P1-4：从 BeadViewModel 下沉的预览画布数学与蒙版平铺）。
/// 覆盖格径缩放下限/画布 clamp/居中偏移/四舍五入、bbox 局部蒙版平铺与越界跳过。
final class BeadPreviewLayoutLogicTests: XCTestCase {

    // MARK: - layout：缩放与居中

    func testLayoutScalesCellAndCentersWithinFloorCanvas() {
        // 20×10 棋盘，格径 10，缩放 2.0 → scaledCell 20；total 400×200
        // 画布 = max(720, 400) = 720；offsetX (720-400)/2 = 160；offsetY (720-200)/2 = 260
        let layout = BeadPreviewLayoutLogic.layout(
            patternWidth: 20, patternHeight: 10, cellSize: 10, canvasScale: 2.0
        )
        XCTAssertEqual(
            layout,
            .init(scaledCell: 20, canvasSize: 720, offsetX: 160, offsetY: 260)
        )
    }

    func testLayoutClampsScaledCellToLowerBound2() {
        // 3 × 0.5 = 1.5 → rounded 2；下限 2 不变（守护过度缩小后格子消失）
        let layout = BeadPreviewLayoutLogic.layout(
            patternWidth: 10, patternHeight: 10, cellSize: 3, canvasScale: 0.5
        )
        XCTAssertEqual(layout.scaledCell, 2)
    }

    func testLayoutRoundsScaledCellToNearest() {
        // 5 × 1.3 = 6.5 → rounded 7（.toNearestOrAwayFromZero 半值远离零）
        let layout = BeadPreviewLayoutLogic.layout(
            patternWidth: 10, patternHeight: 10, cellSize: 5, canvasScale: 1.3
        )
        XCTAssertEqual(layout.scaledCell, 7)
    }

    func testLayoutClampsCanvasToUpperBoundAndZeroOffset() {
        // 200×200 棋盘，格径 20 → total 4000×4000；画布 clamp 2560，棋盘超出 → 偏移 0
        let layout = BeadPreviewLayoutLogic.layout(
            patternWidth: 200, patternHeight: 200, cellSize: 20, canvasScale: 1.0
        )
        XCTAssertEqual(layout.canvasSize, 2560)
        XCTAssertEqual(layout.offsetX, 0)
        XCTAssertEqual(layout.offsetY, 0)
    }

    func testLayoutCentersWideBoardWithFloorCanvasWidth() {
        // 720×360 棋盘（cell 18）→ totalW = 720 = 下限，offsetX 0；totalH 360 → offsetY (720-360)/2 = 180
        let layout = BeadPreviewLayoutLogic.layout(
            patternWidth: 40, patternHeight: 20, cellSize: 18, canvasScale: 1.0
        )
        XCTAssertEqual(
            layout,
            .init(scaledCell: 18, canvasSize: 720, offsetX: 0, offsetY: 180)
        )
    }

    // MARK: - fullMask：bbox 局部蒙版平铺

    func testFullMaskTilesBBoxLocalMaskIntoFullImage() {
        // 4×4 全图，bbox 起点 (1,1) 尺寸 2×2，局部蒙版 [1,2,3,4]
        let seg = SegmentationResult(
            mask: Data([1, 2, 3, 4]), bboxX: 1, bboxY: 1, bboxWidth: 2, bboxHeight: 2
        )
        let full = BeadPreviewLayoutLogic.fullMask(from: seg, imgW: 4, imgH: 4)
        XCTAssertEqual(full, [
            0, 0, 0, 0,
            0, 1, 2, 0,
            0, 3, 4, 0,
            0, 0, 0, 0,
        ])
    }

    func testFullMaskSkipsPixelsOutsideImageBounds() {
        // 4×4 全图，bbox 起点 (-1, 3) 尺寸 2×2：
        // y=0（dstY=3 在界内）：x=0（dstX=-1 越界跳过），x=1（dstX=0 写入 bytes[1]）
        // y=1（dstY=4 越界整行跳过）
        let seg = SegmentationResult(
            mask: Data([9, 8, 7, 6]), bboxX: -1, bboxY: 3, bboxWidth: 2, bboxHeight: 2
        )
        let full = BeadPreviewLayoutLogic.fullMask(from: seg, imgW: 4, imgH: 4)
        XCTAssertEqual(full[3 * 4 + 0], 8)
        XCTAssertEqual(full.filter { $0 != 0 }, [8])
    }

    func testFullMaskEmptyBBoxReturnsAllZero() {
        let seg = SegmentationResult(
            mask: Data(), bboxX: 0, bboxY: 0, bboxWidth: 0, bboxHeight: 0
        )
        let full = BeadPreviewLayoutLogic.fullMask(from: seg, imgW: 3, imgH: 2)
        XCTAssertEqual(full, [UInt8](repeating: 0, count: 6))
    }
}
