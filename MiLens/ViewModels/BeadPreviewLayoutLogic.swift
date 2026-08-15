//  BeadPreviewLayoutLogic —— 拼豆结果预览画布布局纯决策逻辑。
//  从 BeadViewModel 下沉（audit-6 P1-4：0% 覆盖大文件补测）。
//  纯决策逻辑，无 IO/无 SwiftUI 依赖（DESIGN.md §4）。

import Foundation

/// 拼豆预览画布数学与分割蒙版平铺（对照源端 BeadPatternResult.redrawCanvas）。
enum BeadPreviewLayoutLogic {

    /// 画布布局参数：缩放后格径、画布边长与居中偏移。
    struct Layout: Equatable {
        let scaledCell: Int
        let canvasSize: Int
        let offsetX: Int
        let offsetY: Int
    }

    /// 按格径 × 缩放推导画布参数：
    /// - scaledCell 下限 2（避免过度缩小后格子消失）；
    /// - 画布边长 clamp 到 [720, 2560]（下限保证小图可读，上限控制内存）；
    /// - 棋盘在画布内居中，超出侧偏移为 0。
    static func layout(patternWidth: Int, patternHeight: Int, cellSize: Int, canvasScale: Double) -> Layout {
        let scaledCell = Swift.max(2, Int((Double(cellSize) * canvasScale).rounded()))
        let totalW = patternWidth * scaledCell
        let totalH = patternHeight * scaledCell
        let canvasSize = Swift.min(2560, Swift.max(720, Swift.max(totalW, totalH)))
        let offsetX = Swift.max(0, (canvasSize - totalW) / 2)
        let offsetY = Swift.max(0, (canvasSize - totalH) / 2)
        return Layout(scaledCell: scaledCell, canvasSize: canvasSize, offsetX: offsetX, offsetY: offsetY)
    }

    /// iOS SegmentationResult.mask 是 bbox 局部蒙版；平铺到全图坐标
    /// （源端蒙版为全图坐标）再裁切。越界行/列跳过。
    static func fullMask(from seg: SegmentationResult, imgW: Int, imgH: Int) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: imgW * imgH)
        let bytes = [UInt8](seg.mask)
        for y in 0..<seg.bboxHeight {
            let dstY = Int(seg.bboxY) + y
            guard dstY >= 0, dstY < imgH else { continue }
            for x in 0..<seg.bboxWidth {
                let dstX = Int(seg.bboxX) + x
                guard dstX >= 0, dstX < imgW else { continue }
                mask[dstY * imgW + dstX] = bytes[y * seg.bboxWidth + x]
            }
        }
        return mask
    }
}
