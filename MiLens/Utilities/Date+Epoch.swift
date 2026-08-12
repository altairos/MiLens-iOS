//  Date+Epoch —— 日期选择器的共享最早边界。
//  消除 PetEditView / AddPetSheet / AddMemorySheet 中重复的 2000-01-01 构造与 fatalError。

import Foundation

extension Date {
    /// 日期选择器的最早边界（2000-01-01，Gregorian）。
    ///
    /// 2000-01-01 在 Gregorian 日历必然有效；构造失败属于日历基础设施异常，
    /// 显式崩溃并携带原因以便诊断（与原各处内联 fatalError 语义一致）。
    static let milensEpochStart: Date = {
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: DateComponents(year: 2000, month: 1, day: 1)) else {
            fatalError("无法构造 2000-01-01 日期（Gregorian 日历异常）")
        }
        return date
    }()
}
