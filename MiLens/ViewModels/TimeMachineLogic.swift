//  TimeMachineLogic —— 时光机选片与结果构建纯决策逻辑
//  （对应源端 services/TimeMachineService.ets）。
//
//  从历史照片中选出一张推送时光机回忆，构建通知数据（标题/正文/ID）。
//  源端的随机选片用 randomIndex 参数化，保证测试可复现。
//
//  纯函数：不依赖 Repository / UserNotifications / SwiftData。
//  宿主（NotifyService）负责 IO（查照片/查宠物/发通知）。
//
//  架构差异：
//  - 源端直接操作 Photo/Pet 模型实例（含 petId 整数引用）；
//    iOS 用轻量投影 struct，脱离 SwiftData @Model 以便纯逻辑测试。
//  - 源端 Math.floor(Math.random() * len) 随机选片；
//    iOS 用 randomIndex % len 模运算，调用方传入随机种子。
//  - 源端 petName 默认值 '小宝贝' 写在 service 内部；
//    iOS 作为默认参数，可在调用方覆盖。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 投影类型（脱离 SwiftData @Model 以便纯逻辑测试）

/// 时光机选片用的照片投影。
struct TimeMachinePhoto: Equatable, Sendable {
    let id: UUID
    let takenAt: Date?
    let note: String
    let petID: UUID?

    init(id: UUID = UUID(), takenAt: Date? = nil, note: String = "", petID: UUID? = nil) {
        self.id = id
        self.takenAt = takenAt
        self.note = note
        self.petID = petID
    }
}

/// 时光机选片用的宠物投影。
struct TimeMachinePet: Equatable, Sendable {
    let id: UUID
    let name: String

    init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
    }
}

// MARK: - 通知结果数据

/// 时光机通知构建结果。宿主据此创建 `UNNotificationRequest`。
struct TimeMachineNotificationData: Equatable, Sendable {
    /// 通知标题（如 "2年前的今天"）
    let title: String
    /// 通知正文（暖心文案）
    let body: String
    /// 通知标识符（基数 + 月×100 + 日）
    let identifier: Int
    /// 选中照片的 ID（宿主可用于通知附件图片）
    let photoID: UUID
}

// MARK: - 选片决策

/// 从历史照片列表中按索引选出一张。
/// 对应源端 `historicalPhotos[Math.floor(Math.random() * len)]`。
///
/// - Parameters:
///   - photos: 已过滤为「历史照片」的列表（拍摄年 < 今年）
///   - randomIndex: 随机种子（调用方可用 Int.random(in:) 生成）
/// - Returns: 选中照片；空列表返回 nil
func selectTimeMachinePhoto(_ photos: [TimeMachinePhoto], randomIndex: Int) -> TimeMachinePhoto? {
    guard !photos.isEmpty else { return nil }
    let safeIndex = ((randomIndex % photos.count) + photos.count) % photos.count
    return photos[safeIndex]
}

// MARK: - 结果构建

/// 构建时光机通知完整数据。
/// 对应源端 `TimeMachineService.checkAndNotify` 的纯逻辑部分。
///
/// - Parameters:
///   - photo: 选中的历史照片
///   - pets: 全部宠物列表（用于查 petID → name）
///   - now: 当前时间
///   - templateIndex: 文案模板索引（0–3 循环）
///   - defaultPetName: 宠物名缺失时的默认值（nil 时用本地化默认名；源端为 "小宝贝"）
///   - locale: 文案语言（默认当前环境；测试传固定 locale）
/// - Returns: 通知数据（标题 + 正文 + ID + 照片ID）
func buildTimeMachineResult(
    photo: TimeMachinePhoto,
    pets: [TimeMachinePet],
    now: Date,
    templateIndex: Int,
    defaultPetName: String? = nil,
    locale: Locale = .current
) -> TimeMachineNotificationData {
    let calendar = utcCalendar
    let nowYear = calendar.component(.year, from: now)
    let photoYear = (photo.takenAt.map { calendar.component(.year, from: $0) }) ?? nowYear
    let yearsAgo = nowYear - photoYear

    let petName: String
    if let petID = photo.petID,
       let pet = pets.first(where: { $0.id == petID }) {
        petName = pet.name
    } else {
        petName = defaultPetName ?? String(localized: "notify.defaultPetName", locale: locale)
    }

    let text = buildTimeMachineText(
        petName: petName, yearsAgo: yearsAgo, note: photo.note, index: templateIndex, locale: locale)

    let month = calendar.component(.month, from: now)
    let day = calendar.component(.day, from: now)

    return TimeMachineNotificationData(
        // 复数 key（notify.timemachine.title %lld）：en/de/fr 需 one/other 变体
        title: String(localized: "notify.timemachine.title \(yearsAgo)", locale: locale),
        body: text,
        identifier: timeMachineNotificationID(month: month, day: day),
        photoID: photo.id
    )
}

// MARK: - 纪念日通知批量构建

/// 纪念日通知的每张照片通知数据。
struct AnniversaryNotificationData: Equatable, Sendable {
    let title: String
    let body: String
    /// 源端用 photo.id 做 notification request id；iOS 用 UUID hashValue
    let identifier: Int
    let photoID: UUID
}

/// 为一组照片构建纪念日通知数据。
/// 对应源端 `NotifyScheduler.checkAnniversaryEvents` + `sendAnniversaryNotification`。
///
/// - Parameters:
///   - photos: 同一天拍摄的照片列表
///   - now: 当前时间
///   - locale: 文案语言（默认当前环境；测试传固定 locale）
/// - Returns: 每张照片一个通知数据
func buildAnniversaryNotifications(
    photos: [TimeMachinePhoto],
    now: Date,
    locale: Locale = .current
) -> [AnniversaryNotificationData] {
    let calendar = utcCalendar
    let nowYear = calendar.component(.year, from: now)

    return photos.map { photo in
        let photoYear = (photo.takenAt.map { calendar.component(.year, from: $0) }) ?? nowYear
        let yearsAgo = nowYear - photoYear
        let text = buildAnniversaryNotificationText(yearsAgo: yearsAgo, note: photo.note, locale: locale)
        // 源端用 photo.id（整数）做 notification id；iOS 用 UUID 做 identifier 字符串 hash
        return AnniversaryNotificationData(
            title: String(localized: "notify.anniversary.title", locale: locale),
            body: text,
            identifier: photo.id.hashValue,
            photoID: photo.id
        )
    }
}
