//  MeasureBaselineTests —— 关键算法性能基准（评审阻塞项：工程无 measure 基准）。
//
//  Xcode 中首次运行仅记录结果（无基线不失败）；在「性能」报告里可对用例
//  Edit → Set Baseline 固化基线，后续跑分超出 ±容忍度即回归告警。
//  选点原则：拼豆生成/导出热路径（图纸像素渲染、源图裁切），对应源端
//  Canvas 绘制与 loadPhotoPixels 裁剪——CPU 密集、纯逻辑、可稳定复现。

import XCTest
import MiLensKit

final class MeasureBaselineTests: XCTestCase {

    /// 构造 29×29 单色图纸（无空位、单一 MARD 色），覆盖完整绘制循环。
    private func makePattern(width: Int, height: Int) -> BeadPattern {
        let count = width * height
        return BeadPattern(
            width: width,
            height: height,
            indices: [UInt16](repeating: 0, count: count),
            empty: [UInt8](repeating: 0, count: count),
            paletteUsed: [
                BeadColor(
                    id: "perf-test",
                    name: "性能测试色",
                    rgb: RGBColor(220, 30, 30),
                    symbol: "P",
                    brand: "perf"
                )
            ]
        )
    }

    /// 图纸像素渲染：29×29 图纸 → 232×232 RGBA 缓冲（含网格线）。
    func testMeasureDrawBeadPattern() {
        let pattern = makePattern(width: 29, height: 29)
        let canvasSize = 29 * 8
        var pixels = [UInt8](repeating: 0, count: canvasSize * canvasSize * 4)

        measure {
            drawBeadPattern(
                pixels: &pixels,
                canvasW: canvasSize,
                canvasH: canvasSize,
                pattern: pattern,
                cellSize: 8,
                viewMode: "color",
                offsetX: 0,
                offsetY: 0
            )
        }
    }

    /// 源图正方形裁切：1080×1080 RGBA → 900×900（生成管线入口热点）。
    func testMeasureCropPixelsToSquare() {
        let srcW = 1080
        let fullPixels = [UInt8](repeating: 128, count: srcW * srcW * 4)

        measure {
            _ = cropPixelsToSquare(
                fullPixels, srcW: srcW,
                cropX: 90, cropY: 90, cropSize: 900
            )
        }
    }
}
