//  ScanFlowLogic —— 扫描流程决策纯逻辑
//  （对应源端 viewmodels/ScanFlowViewModel.ets）。
//
//  把扫描操作结果（error/canceled/result=null 三态）映射为可测的动作枚举，
//  宿主据此更新扫描状态并决定文案。扫描完成文案构造脱离实例，便于单测固化。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

/// 扫描结果（对应源端 services/PhotoScanner.ets ScanResult）
struct ScanResult: Equatable, Sendable {
    var matchedCount: Int
    var unassignedPetUris: [String]
    /// 实际经过 AI 检测处理的照片数（排除已导入和按时间过滤跳过的）
    var processedCount: Int
    var canceled: Bool

    init(matchedCount: Int = 0, unassignedPetUris: [String] = [],
         processedCount: Int = 0, canceled: Bool = false) {
        self.matchedCount = matchedCount
        self.unassignedPetUris = unassignedPetUris
        self.processedCount = processedCount
        self.canceled = canceled
    }
}

/// 扫描操作返回的三态快照（对应源端 ScanOpSnapshot）
struct ScanOpSnapshot: Equatable, Sendable {
    var error: String
    var canceled: Bool
    /// nil 表示暂停（result 尚未产出）；非 nil 表示完成
    var result: ScanResult?
}

/// 扫描流程应执行的动作（对应源端 ScanFlowAction）
enum ScanFlowAction: Equatable, Sendable {
    case showError       // 有错误：toast + 停止扫描状态
    case showCanceled    // 用户取消：重置进度 + toast
    case setPaused       // 暂停：保持 isScanning
    case proceedComplete // 正常完成：处理结果
}

enum ScanFlowLogic {

    /// 解析扫描操作结果，返回应执行的动作。
    /// 优先级：error → canceled → result=nil(暂停) → 正常完成。
    static func resolveFlow(_ op: ScanOpSnapshot) -> ScanFlowAction {
        if !op.error.isEmpty { return .showError }
        if op.canceled { return .showCanceled }
        if op.result == nil { return .setPaused }
        return .proceedComplete
    }

    /// 构造扫描完成文案（纯函数版 ScanController.buildScanCompleteMessage）。
    /// - Parameters:
    ///   - matchedCount: 已匹配到已注册宠物的照片数
    ///   - unassignedCount: 检测到猫狗但未匹配的照片数
    ///   - processedCount: 实际经过 AI 检测的照片数
    ///   - isNewOnly: 是否为「仅扫描新增」
    static func resolveCompleteMessage(
        matchedCount: Int, unassignedCount: Int,
        processedCount: Int, isNewOnly: Bool
    ) -> String {
        var msg = isNewOnly
            ? "新扫描 \(processedCount) 张照片。"
            : "共扫描 \(processedCount) 张照片。"
        if matchedCount > 0 {
            msg += "\n其中 \(matchedCount) 张照片属于已注册的伙伴。"
        }
        if unassignedCount > 0 {
            msg += "\n另发现 \(unassignedCount) 张照片也包含猫或狗，但特征与已注册的伙伴不太相符。"
        }
        if matchedCount == 0 && unassignedCount == 0 {
            msg += "\n未发现任何包含猫或狗的照片。"
        }
        return msg
    }
}
