//  HomeDateSupport —— MiLensKit 纯逻辑共享日期工具（内部）。
//
//  固定 UTC Calendar，与 App 层 AnniversaryLogic.utcCalendar 保持同一约定：
//  跨环境可复现（测试可在任意时区机器运行）。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

/// MiLensKit 纯逻辑共享的固定 UTC Calendar（Home/Gallery 等模块共用）。
let miLensUTCCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Home 模块沿用旧名的别名（指向同一实例）。
let homeUTCCalendar = miLensUTCCalendar
