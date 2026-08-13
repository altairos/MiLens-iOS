//  BellShakeLogic —— 首页铃铛晃动触发原因的纯决策逻辑。
//
//  决定铃铛是否晃动、以及点击铃铛后应执行的动作分流。
//  纯函数：不依赖 IO / UserDefaults / SwiftUI，宿主层传入原始布尔信号与用户开关。
//
//  ShakeMode 是用户偏好（@AppStorage 持久化），决定哪些提醒类型允许触发晃动；
//  TriggerReason 是经开关过滤后的最终触发原因，决定晃动与点击分流。

import Foundation

public enum BellShakeLogic {

    /// 铃铛晃动模式（用户设置，四选一）。
    public enum ShakeMode: String, CaseIterable, Sendable {
        /// 完全关闭晃动。
        case off
        /// 仅新照片提醒时晃动。
        case newPhotoOnly
        /// 仅纪念日提醒时晃动。
        case anniversaryOnly
        /// 全部开启（默认）。
        case all
    }

    /// 铃铛触发原因（经开关过滤后的最终状态）。
    /// 决定晃动与否、点击分流。
    public enum TriggerReason: Equatable, Sendable {
        /// 无提醒或被开关过滤——不晃动，点击兜底进回忆提醒中心。
        case none
        /// 仅纪念日提醒——晃动，点击直接进回忆提醒中心。
        case anniversary
        /// 仅新照片提醒——晃动，点击弹确认窗。
        case newPhoto
        /// 纪念日 + 新照片——晃动，点击弹选择菜单。
        case both
    }

    // MARK: - 触发原因解析

    /// 根据原始提醒信号与用户开关，计算最终的触发原因。
    /// - Parameters:
    ///   - hasAnniversary: 今日是否有纪念日命中（生日/成为家人的日子/里程碑/往日回忆）。
    ///   - hasNewPhoto: 是否有新照片提醒（系统图库有新照片 OR 久未添加）。
    ///   - mode: 用户晃动开关。
    /// - Returns: 经开关过滤后的触发原因。
    public static func resolveReason(
        hasAnniversary: Bool, hasNewPhoto: Bool, mode: ShakeMode
    ) -> TriggerReason {
        let anniversaryAllowed = hasAnniversary && (mode == .anniversaryOnly || mode == .all)
        let newPhotoAllowed = hasNewPhoto && (mode == .newPhotoOnly || mode == .all)
        switch (anniversaryAllowed, newPhotoAllowed) {
        case (true, true): return .both
        case (true, false): return .anniversary
        case (false, true): return .newPhoto
        case (false, false): return .none
        }
    }

    // MARK: - 晃动判定

    /// 是否应启动晃动动效。
    public static func shouldAnimate(_ reason: TriggerReason) -> Bool {
        reason != .none
    }
}
