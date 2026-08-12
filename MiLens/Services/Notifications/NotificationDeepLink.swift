//  NotificationDeepLink —— 本地通知 tap → 类型安全路由的纯解析逻辑。
//
//  通知调度时已将路由信息编码进通知标识符（milestone-<petID>-<days>），
//  tap 时无需额外 userInfo 解码即可还原目标。当前支持里程碑通知；
//  其余通知（周年/时光机）返回 nil（停留当前页）。
//
//  纯逻辑：标识符字符串 → NotificationTapDestination，无 IO / 无 SwiftUI 依赖。可单测。
//  App 层（AppDelegate + MiLensApp）负责在 tap 时查代表照片并构造最终 Route。

import Foundation
import MiLensKit

/// 通知 tap 的待路由目的地（App 层据此查代表照片后构造 Route）。
struct NotificationTapDestination: Equatable {
    /// 目标宠物 ID。
    let petID: UUID
    /// 卡片类型（决定 PetCardView 渲染分支与文案）。
    let kind: MemoryCardKind
}

enum NotificationDeepLink {

    /// 从通知标识符解析 tap 路由目的地。
    ///
    /// 支持的标识符：
    /// - `milestone-<petID>-<days>` → `.milestone`（petID 为 UUID，含连字符）
    ///
    /// - Parameter identifier: UNNotificationRequest.identifier
    /// - Returns: 解析成功的目的地；非里程碑通知或格式无效时返回 nil
    static func destination(fromIdentifier identifier: String) -> NotificationTapDestination? {
        let prefix = NotifyService.milestoneIdentifierPrefix
        guard identifier.hasPrefix(prefix) else { return nil }
        // 去掉 "milestone-" 前缀后剩 "<petID>-<days>"；petID 是 UUID（含 4 个连字符），
        // 用最后一个 "-" 分隔天数，避免与 UUID 内部连字符冲突。
        let rest = String(identifier.dropFirst(prefix.count))
        guard let lastHyphen = rest.lastIndex(of: "-") else { return nil }
        let petIDString = String(rest[..<lastHyphen])
        guard let petID = UUID(uuidString: petIDString) else { return nil }
        return NotificationTapDestination(petID: petID, kind: .milestone)
    }
}
