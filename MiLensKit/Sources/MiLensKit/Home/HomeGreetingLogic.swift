//  HomeGreetingLogic —— 首页时段问候纯决策逻辑。
//
//  首页 hero 顶部按时段问候（UI-DESIGN.md §5.1：「晚上好」/ 设计稿示例「早上好」）。
//  源端无对应实现（首页 hero 为 iOS 设计稿新增概念），行为规格由本文件 +
//  HomeLogicTests 定义并守护。
//
//  纯函数：hour 参数化（0–23），不依赖系统时间/时区，测试可复现。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

/// 首页时段问候。
public enum HomeGreetingLogic {
    /// 返回指定小时对应的问候语。
    ///
    /// 时段划分：早上好 5–11 时 / 下午好 12–17 时 / 晚上好 18–4 时。
    ///
    /// - Parameters:
    ///   - hour: 本地 0–23 时；越界值按 24 小时模运算归一（-1 → 23，24 → 0）
    /// - Returns: 「早上好」「下午好」或「晚上好」
    public static func greeting(forHour hour: Int) -> String {
        let safeHour = ((hour % 24) + 24) % 24
        switch safeHour {
        case 5...11:
            return "早上好"
        case 12...17:
            return "下午好"
        default:
            return "晚上好"
        }
    }
}
