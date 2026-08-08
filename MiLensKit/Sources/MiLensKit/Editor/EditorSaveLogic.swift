import Foundation

// EditorSaveLogic — 编辑器保存/返回确认决策纯逻辑。
// 翻译自源端 entry/.../viewmodels/EditorSaveViewModel.ets（约 115 行）。
//
// 从 EditorPage 保存/返回确认流程抽出的决策纯逻辑。
//
// 设计要点：
// - 所有函数无 IO / 无 SwiftUI / 无文件系统依赖，可在宿主单测覆盖。
// - 编码（encodePixelMap）/ 写盘（FileService）/ 数据库入库（PhotoRepository）
//   仍在 App 层；本模块只回答"能否开始保存"和"返回时应执行哪个动作"。
// - resolveBackAction 把 handleBack 的 inline if（canUndo → 确认 / 否则直接返回）
//   下沉为可测分支，支持 BlockWhileSaving 防止覆盖写。
// - EXIF 策略不在此重复实现（见 EditorExifPolicy）。

/// 保存/返回决策的页面状态快照。对应源端 `EditorSaveSnapshot`。
public struct EditorSaveSnapshot: Equatable, Sendable {
    /// 是否正在保存（saveTo* 进行中）。
    public var isSaving: Bool
    /// 原图是否正在加载。
    public var isPhotoLoading: Bool
    /// 原图是否已加载完成。
    public var photoLoaded: Bool
    /// 是否存在未保存的编辑（layerManager.canUndo）。
    public var hasUnsavedChanges: Bool

    public init(isSaving: Bool, isPhotoLoading: Bool, photoLoaded: Bool, hasUnsavedChanges: Bool) {
        self.isSaving = isSaving
        self.isPhotoLoading = isPhotoLoading
        self.photoLoaded = photoLoaded
        self.hasUnsavedChanges = hasUnsavedChanges
    }
}

/// 返回键应执行的动作。对应源端 `BackAction`。
public enum EditorBackAction: String, Sendable, Equatable {
    /// 无未保存的动作，直接返回。
    case immediateBack = "immediate-back"
    /// 有未保存的动作，需确认先保存。
    case confirmSaveFirst = "confirm-save-first"
    /// 正在保存，拦截返回避免覆盖写。
    case blockWhileSaving = "block-while-saving"
}

// MARK: - 常量

/// 默认的保存文件名扩展（不含点）。对应源端 `EDIT_EXPORT_EXTENSION`。
public let EDIT_EXPORT_EXTENSION: String = "jpg"
/// 编辑导出文件名前缀。对应源端 `EDIT_EXPORT_PREFIX`。
private let EDIT_EXPORT_PREFIX: String = "MiLens_Edit"

// MARK: - 保存/返回决策

/// 是否可以开始一次新的保存。
/// 保存方法在以下情况拒绝：正在保存 / 原图加载中 / 原图未加载。
/// 对应源端 `canStartSave`。
public func canStartSave(_ snapshot: EditorSaveSnapshot) -> Bool {
    if snapshot.isSaving { return false }
    if snapshot.isPhotoLoading { return false }
    return snapshot.photoLoaded
}

/// 解析返回键动作。
/// 优先级：正在保存 → 拦截；有未保存 → 确认；否则直接返回。
/// 对应源端 `resolveBackAction`。
public func resolveBackAction(_ snapshot: EditorSaveSnapshot) -> EditorBackAction {
    if snapshot.isSaving { return .blockWhileSaving }
    if snapshot.hasUnsavedChanges { return .confirmSaveFirst }
    return .immediateBack
}

// MARK: - 保存格式决策

/// 保存格式决策结果。对应源端 `SaveFormatDecision`。
public struct EditorSaveFormatDecision: Equatable, Sendable {
    /// 图片编码格式（如 "image/jpeg" 或 "image/png"）。
    public let format: String
    /// 编码质量（JPEG 有效；PNG 无损）。
    public let quality: Int
    /// 文件扩展名（不含点，如 "jpg" 或 "png"）。
    public let extension_: String
}

/// 根据照片图层是否有透明通道决定保存格式。
/// - 有透明通道（抠图后）：PNG（保留透明）。
/// - 无透明通道（普通编辑）：JPEG（更小体积，quality=92）。
/// 对应源端 `resolveSaveFormat`。
public func resolveSaveFormat(hasAlpha: Bool) -> EditorSaveFormatDecision {
    if hasAlpha {
        return EditorSaveFormatDecision(format: "image/png", quality: 100, extension_: "png")
    }
    return EditorSaveFormatDecision(format: "image/jpeg", quality: 92, extension_: "jpg")
}

/// 构造编辑导出文件名 `MiLens_Edit_<timestamp>.<ext>`。
/// ext 为空时回退到 jpg。对应源端 `resolveSaveFileNameHint`。
public func resolveSaveFileNameHint(timestamp: Int64, ext: String = EDIT_EXPORT_EXTENSION) -> String {
    let safeExt = ext.isEmpty ? EDIT_EXPORT_EXTENSION : ext
    return "\(EDIT_EXPORT_PREFIX)_\(timestamp).\(safeExt)"
}

/// 构造编辑导出文件名（使用 SaveFormatDecision 提供的扩展名）。
/// 对应源端 `resolveSaveFileNameHintWithDecision`。
public func resolveSaveFileNameHint(timestamp: Int64, decision: EditorSaveFormatDecision) -> String {
    return "\(EDIT_EXPORT_PREFIX)_\(timestamp).\(decision.extension_)"
}
