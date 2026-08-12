//  WidgetReload —— Widget 数据变更通知机制。
//
//  WidgetKit-Design.md §6.1：主 App 在以下事件后更新 App Group 快照：
//  - 导入、删除或重新归属照片；
//  - 新建/编辑伙伴档案与纪念事件；
//  - 添加记忆或生成新作品。
//
//  采用 NotificationCenter 解耦：ViewModel / Service 不持有 WidgetSnapshotWriter，
//  只需 post 通知；MiLensApp 统一监听并触发快照写入。避免给每个 ViewModel 改构造函数。

import Foundation

extension Notification.Name {
    /// Widget 数据变更通知（照片导入/删除、宠物 CRUD、记忆添加等）。
    static let widgetDataChanged = Notification.Name("MiLensWidgetDataChanged")
}

enum WidgetReload {
    /// 通知主 App 重新写入 Widget 快照。
    /// 在数据变更操作完成后调用（导入完成、宠物保存、记忆添加、照片删除等）。
    static func notifyDataChanged() {
        NotificationCenter.default.post(name: .widgetDataChanged, object: nil)
    }
}
