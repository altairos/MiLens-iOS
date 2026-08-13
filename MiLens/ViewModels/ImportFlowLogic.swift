//  ImportFlowLogic —— 导入流程决策纯逻辑
//  （对应源端 viewmodels/ImportFlowViewModel.ets）。
//
//  把导入模式 → 管线决策的映射和默认分类构造抽为纯函数，便于单测固化。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

/// 导入模式（对应源端 services/PhotoScanner.ets ImportMode）
enum ImportMode: Int, Sendable, Equatable {
    case autoMatch = 0       // 仅导入检测到宠物且匹配到档案的照片
    case importAll = 1       // 导入所有照片，导入后尝试匹配
    case importUnassigned = 2 // 导入未归属的宠物照片
}

/// 导入管线决策结果（对应源端 ImportModeDecision）
struct ImportModeDecision: Equatable, Sendable {
    /// importAll / importUnassigned 跳过 AI 检测
    let skipDetection: Bool
    /// importUnassigned 跳过自动匹配（只入未分配池）
    let skipAutoMatch: Bool
    /// 日志标签
    let modeLabel: String
}

/// 检测/分类结果（对应源端 services/VisionClassifier.ets ClassificationResult）。
/// V1.0 用字符串标签，不绑定系统枚举，便于 mock。
struct ClassificationResult: Equatable, Sendable {
    var category: String   // "pet_photo" / "non_pet" / "unknown"
    var subCategory: String // "cat" / "dog" / "other"
    var label: String
    var confidence: Double

    /// 默认空分类（对应源端 CLASS_DEFAULT）
    static let empty = ClassificationResult(
        category: "unknown", subCategory: "other", label: "", confidence: 0
    )

    /// 未归属宠物默认分类（PET_PHOTO/OTHER）
    static let unassignedPet = ClassificationResult(
        category: "pet_photo", subCategory: "other",
        label: "unassigned_pet_confirmed_by_scan", confidence: 1.0
    )
}

enum ImportFlowLogic {

    /// 将 ImportMode 映射为管线决策（对应源端 resolveImportModeDecision）。
    /// - autoMatch：全量管线（检测+匹配）
    /// - importAll：跳过检测但保留匹配
    /// - importUnassigned：跳过检测和匹配，直接入未分配池
    static func resolveModeDecision(_ mode: ImportMode) -> ImportModeDecision {
        switch mode {
        case .autoMatch:
            return ImportModeDecision(skipDetection: false, skipAutoMatch: false, modeLabel: "auto-match")
        case .importUnassigned:
            return ImportModeDecision(skipDetection: true, skipAutoMatch: true, modeLabel: "unassigned")
        case .importAll:
            return ImportModeDecision(skipDetection: true, skipAutoMatch: false, modeLabel: "all")
        }
    }

    /// 返回给定导入模式的默认 ClassificationResult（对应源端 resolveDefaultClassification）。
    /// importUnassigned 给出 PET_PHOTO/OTHER 默认值；其余返回 empty（待检测管线填充）。
    static func resolveDefaultClassification(_ mode: ImportMode) -> ClassificationResult {
        mode == .importUnassigned ? .unassignedPet : .empty
    }

    /// 导入完成汇总消息（自动归属结果提示）。
    /// 仅 matched > 0 时提及自动归属；failed > 0 时追加失败提示，避免静默丢照片（H4）。
    /// cancelled = true 时追加取消提示，让调用方区分「用户取消」与「普通完成」。
    static func resolveImportSummary(
        imported: Int, matched: Int, failed: Int, cancelled: Bool = false
    ) -> String {
        if imported <= 0 {
            if cancelled { return "导入已取消" }
            return failed > 0 ? "有 \(failed) 张照片导入失败" : "没有新照片需要导入"
        }
        var message = "已导入 \(imported) 张照片"
        if matched > 0 { message += "，其中 \(matched) 张自动归入已注册宠物" }
        if failed > 0 { message += "，\(failed) 张导入失败" }
        if cancelled { message += "（已取消）" }
        return message
    }
}
