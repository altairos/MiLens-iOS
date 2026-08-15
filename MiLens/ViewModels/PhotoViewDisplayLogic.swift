//  PhotoViewDisplayLogic —— 照片详情页展示文案纯决策逻辑。
//  从 PhotoViewView 下沉（audit-6 P1-4：0% 覆盖大文件补测）。
//  手势/坐标数学已在 PhotoViewGestureMath；本文件只管信息 Sheet 文案。
//  纯决策逻辑，无 IO/无 SwiftUI 依赖（DESIGN.md §4）。

import Foundation

/// 照片详情展示文案决策（对照 Figma「08·照片详情」#211:316 Information Sheet）。
enum PhotoViewDisplayLogic {

    /// 拍摄日期标签："YYYY年M月D日 · HH:MM"（源端硬编码中文格式串，locale 无关）。
    /// calendar 注入以便测试跨日历可复现（沿用 TimelineLogic.isoDateString 惯例）。
    static func dateLabel(takenAt: Date?, calendar: Calendar = .current) -> String {
        guard let takenAt else { return "" }
        let year = calendar.component(.year, from: takenAt)
        let month = calendar.component(.month, from: takenAt)
        let day = calendar.component(.day, from: takenAt)
        let hour = calendar.component(.hour, from: takenAt)
        let minute = calendar.component(.minute, from: takenAt)
        return String(format: "%d年%d月%d日 · %02d:%02d", year, month, day, hour, minute)
    }

    /// 标题：有手写笔记返回笔记，否则回退「已归档」占位。
    static func titleText(note: String) -> String {
        note.isEmpty ? String(localized: "photo.detail.archived") : note
    }

    /// 元数据行："宠物名 · 已归档"；无宠物关联时仅「已归档」。
    static func metadataText(petName: String) -> String {
        let archived = String(localized: "photo.detail.archived")
        if petName.isEmpty {
            return archived
        }
        return "\(petName) · \(archived)"
    }
}
