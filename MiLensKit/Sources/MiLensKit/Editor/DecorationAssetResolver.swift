import Foundation

// DecorationAssetResolver — 装饰素材 resourcePath 运行时解析（纯函数）。
//
// 预览（EditorCanvasView）与导出（renderExport）共用同一解析规则，
// 消除"仅导出走 imageProvider 选图、预览只有单图"的不一致：
// - stretch / ninePatch：resourcePath 原样（单 PNG；ninePatch 的分块由渲染层处理）。
// - ratioSet：按目标比例（照片 width/height）在 supportedRatios 中选最近 token，
//   实际素材名为 "{resourcePath}_{token}"（如 "frame_polaroid_3x4"）。
//
// 候选为空、token 全部非法或目标比例非法时退回 resourcePath（单素材兜底，不崩）。

/// 解析装饰项在给定目标比例下的实际素材路径。
///
/// - Parameters:
///   - item: 装饰目录项（frame 的 fitMode 决定解析规则；sticker 恒 stretch）。
///   - targetRatio: 目标宽高比（width / height，通常为照片层比例；须 > 0 且有限）。
/// - Returns: 最终素材路径；ratioSet 匹配失败或非 ratioSet 模式时返回 `item.resourcePath`。
public func resolveDecorationResource(item: DecorationItem, targetRatio: Double) -> String {
    guard item.fitMode == .ratioSet,
          targetRatio > 0, targetRatio.isFinite,
          let ratios = item.supportedRatios, !ratios.isEmpty,
          let token = pickClosestAspectRatio(targetRatio: targetRatio, candidates: ratios)
    else { return item.resourcePath }
    return "\(item.resourcePath)_\(token)"
}
