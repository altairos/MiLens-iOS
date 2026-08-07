//  PetEvent @Model —— 宠物纪念事件（对应源端 pet_event_table + models/PetEvent.ets）。
//  生日/领养日等纪念提醒用。

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

    init(
        id: UUID = UUID(),
        pet: Pet? = nil,
        eventType: String,
        eventDate: Date,
        title: String,
        notify: Bool = true
    ) {
        self.id = id
        self.pet = pet
        self.eventType = eventType
        self.eventDate = eventDate
        self.title = title
        self.notify = notify
    }
}
