//  ExportQuality —— 作品导出规格枚举（ADR-0010 §10.13）。
//
//  统一各导出路径（宠物卡片、成长对比、时间线长图、回忆册）的像素上限与压缩质量。
//  免费版标准导出保留水印；Pro 版高清导出无水印。
//  所有高清导出必须经过尺寸上限、取消检查和临时文件清理，不能因商业化绕过
//  资源生命周期规则（DESIGN.md §3 / ADR-0010 §10.13）。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

/// 导出画质规格（ADR-0010 §10.13）。
public enum ExportQuality: String, CaseIterable, Identifiable, Equatable, Sendable {

    /// 标准分辨率（免费版默认，带水印）。
    case standard
    /// 高清分辨率（Pro 版，无水印）。
    case high

    public var id: String { rawValue }

    /// 导出画布长边像素上限。
    /// standard 对齐 PetCardLogic.exportSize（1080px）；high 提升到 2400px（真机校准后可调）。
    public var maxLongEdgePixels: Int {
        switch self {
        case .standard: return 1080
        case .high:     return 2400
        }
    }

    /// JPEG 压缩质量（0…1）。
    public var jpegCompressionQuality: Double {
        switch self {
        case .standard: return 0.9
        case .high:     return 0.95
        }
    }

    /// 是否为 Pro 专属画质。
    public var isPremium: Bool {
        self == .high
    }

    /// 判断指定画质在给定 Pro 状态下是否可用；不可用时回退到 standard。
    public func resolved(isPro: Bool) -> ExportQuality {
        (isPremium && !isPro) ? .standard : self
    }

    /// 根据原始尺寸与画质，计算实际导出尺寸（保持宽高比，长边不超过上限）。
    public func scaledSize(originalWidth: Int, originalHeight: Int) -> (width: Int, height: Int) {
        let maxEdge = maxLongEdgePixels
        let longEdge = max(originalWidth, originalHeight)
        guard longEdge > maxEdge else {
            return (originalWidth, originalHeight)
        }
        let scale = Double(maxEdge) / Double(longEdge)
        let w = max(1, Int(Double(originalWidth) * scale))
        let h = max(1, Int(Double(originalHeight) * scale))
        return (w, h)
    }
}
