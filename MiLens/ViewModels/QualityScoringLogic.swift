//  QualityScoringLogic —— 照片质量评分纯公式
//  （对应源端 utils/ImageUtils.ets computeQualityScore）。
//
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。
//  加权公式：0.4×清晰度 + 0.3×宠物因子 + 0.3×分辨率。

import Foundation

/// 照片质量评分纯逻辑（对应源端 `ImageUtils.computeQualityScore`）。
enum QualityScoringLogic {
    /// 清晰度归一化上限（Laplacian 方差达到此值即满分，对应源端 `sharpness / 5000`）。
    static let sharpnessCeiling: Double = 5000
    /// 全高清像素数（分辨率归一化基准，对应源端 `1920 * 1080`）。
    static let fullHDPixels: Double = 1_920 * 1_080

    /// 计算照片质量评分（0…1）。
    /// - Parameters:
    ///   - sharpness: Laplacian 方差清晰度（对应源端 `ImageUtils.computeSharpness`）
    ///   - hasPet: 是否已归属宠物（true = 1.0 加权，false = 0.5 加权）
    ///   - width: 照片像素宽
    ///   - height: 照片像素高
    /// - Returns: 加权评分 `0.4×clarityNorm + 0.3×petScore + 0.3×resolutionScore`
    static func computeQualityScore(sharpness: Double, hasPet: Bool, width: Int, height: Int) -> Double {
        let clarityNorm = min(sharpness / sharpnessCeiling, 1.0)
        let petScore: Double = hasPet ? 1.0 : 0.5
        let resolutionScore = min(Double(width * height) / fullHDPixels, 1.0)
        return 0.4 * clarityNorm + 0.3 * petScore + 0.3 * resolutionScore
    }
}
