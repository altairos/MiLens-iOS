//  PetEvent @Model —— 宠物纪念事件（对应源端 pet_event_table + models/PetEvent.ets）。
//  生日/领养日等纪念提醒用；V2 扩展支持用户记录（body/sourceType）与关联照片。
//
//  SchemaV2 新增字段（均为可空或有默认值，lightweight migration 安全）：
//  - body：用户记录正文（空字符串=纯事件，非空=用户文本记忆）
//  - sourceType：来源标签 "system"(默认) / "user" / "work"
//  - isPinned：置顶状态（Life-Archive-Design.md §2 P0）
//  - relatedPhotoID：关联照片（可选）

import Foundation
import SwiftData

@Model
final class PetEvent {
    @Attribute(.unique) var id: UUID
    var pet: Pet?
    /// 事件类型："birthday" / "adoption"（源端 eventType 字符串）
    var eventType: String
    var eventDate: Date
    var title: String
    /// 是否启用通知提醒（对应源端 notify）
    var notify: Bool

    // MARK: SchemaV2 新增字段

    /// 用户记录正文（空=纯事件，非空=用户文本记忆，Life-Archive-Design.md §2）。
    var body: String
    /// 来源标签："system"(系统推导) / "user"(用户记录) / "work"(作品记录)。
    var sourceType: String
    /// 是否置顶（档案首页首屏展示，Life-Archive-Design.md §2 P0）。
    var isPinned: Bool
    /// 关联照片 ID（用户记录可关联一张代表照片，可选）。
    var relatedPhotoID: UUID?

    init(
        id: UUID = UUID(),
        pet: Pet? = nil,
        eventType: String,
        eventDate: Date,
        title: String,
        notify: Bool = true,
        body: String = "",
        sourceType: String = "system",
        isPinned: Bool = false,
        relatedPhotoID: UUID? = nil
    ) {
        self.id = id
        self.pet = pet
        self.eventType = eventType
        self.eventDate = eventDate
        self.title = title
        self.notify = notify
        self.body = body
        self.sourceType = sourceType
        self.isPinned = isPinned
        self.relatedPhotoID = relatedPhotoID
    }
}
