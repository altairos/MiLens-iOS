//  AnniversaryLogic —— 周年纪念日期与文案纯决策逻辑
//  （对应源端 database/PhotoQueryLogic.ets 中的日期格式化函数
//   + services/NotifyScheduler.ets getYearsAgo / 文案生成）。
//
//  纯函数：不依赖 Repository / UserNotifications / SwiftData。
//  宿主（NotifyService / HomeViewModel）负责 IO 与实际通知调度。
//
//  架构差异：
//  - 源端 getYearsAgo 用 new Date(string).getFullYear() 直接相减；
//    iOS 用 Calendar + DateComponents，保证跨时区可复现。
//  - 源端 formatAnniversaryMonthDay 用 String.padStart；
//    iOS 用 String(format: "%02d")，行为一致。
//  - 源端 LIKE 模式用于 RDB SQL 查询；iOS SwiftData 不用 LIKE，
//    但保留模式函数供 DateComponents 谓词构建参考与 parity 断言。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 日期格式化

/// 把月份和日期格式化为 "MM-DD"（带前导零）。
/// 对应源端 `formatAnniversaryMonthDay`。
///
/// - Parameters:
///   - month: 1–12
///   - day: 1–31
/// - Returns: "MM-DD"（如 (3, 5) → "03-05"）
func formatAnniversaryMonthDay(_ month: Int, _ day: Int) -> String {
    String(format: "%02d-%02d", month, day)
}

// MARK: - 年份差计算

/// 计算从某日期到「现在」的整年数差。
/// 对应源端 `NotifyScheduler.getYearsAgo`。
///
/// - Parameters:
///   - dateStr: ISO 8601 字符串（如 "2024-06-15T10:00:00"）
///   - now: 当前时间（注入保证测试可复现）
/// - Returns: 年份差（now.year - date.year）；空串或解析失败返回 0
func computeYearsAgo(fromDateString dateStr: String, now: Date) -> Int {
    guard !dateStr.isEmpty,
          let date = parseISODate(dateStr) else { return 0 }
    let calendar = utcCalendar
    let nowYear = calendar.component(.year, from: now)
    let dateYear = calendar.component(.year, from: date)
    return nowYear - dateYear
}

/// 判断一张照片是否为「历史照片」（拍摄年份严格早于当前年份）。
/// 对应源端 TimeMachineService 的 `historicalPhotos` 过滤逻辑。
///
/// - Parameters:
///   - takenAt: 照片拍摄日期
///   - now: 当前时间
/// - Returns: true 如果 takenAt 的年份 < now 的年份
func isHistoricalPhoto(takenAt: Date?, now: Date) -> Bool {
    guard let takenAt else { return false }
    let calendar = utcCalendar
    return calendar.component(.year, from: takenAt) < calendar.component(.year, from: now)
}

// MARK: - 纪念日通知文案

/// 纪念日通知文案。对应源端 `NotifyScheduler.sendAnniversaryNotification` 的文案逻辑。
///
/// - Parameters:
///   - yearsAgo: 年份差（0 表示今年的照片）
///   - note: 照片备注
/// - Returns: 通知正文
func buildAnniversaryNotificationText(yearsAgo: Int, note: String) -> String {
    if yearsAgo > 0 {
        return "\(yearsAgo)年前的今天：\(note)"
    } else {
        return "今天的回忆：\(note)"
    }
}

// MARK: - 时光机文案生成

/// 时光机暖心文案。对应源端 `TimeMachineService.generateWarmText`。
///
/// 源端用 `templates[random]` 随机选择；iOS 为可测纯函数，
/// 按索引返回固定模板，调用方可传入随机索引。
///
/// - Parameters:
///   - petName: 宠物名称（空时由调用方传入默认名）
///   - yearsAgo: 年份差
///   - note: 照片备注（可为空）
///   - index: 模板索引（0–3），模运算循环
/// - Returns: 文案字符串
func buildTimeMachineText(petName: String, yearsAgo: Int, note: String, index: Int) -> String {
    let templates = [
        "\(yearsAgo)年前的今天，\(petName)在做什么呢？",
        "\(yearsAgo)年前的今天，\(petName)这样陪伴着你",
        note.isEmpty
            ? "时光飞逝，\(yearsAgo)年前的今天"
            : "时光飞逝，\(yearsAgo)年前的今天，\(note)",
        "回忆杀！\(yearsAgo)年前\(petName)还是这般模样",
    ]
    let safeIndex = ((index % templates.count) + templates.count) % templates.count
    return templates[safeIndex]
}

// MARK: - 通知 ID 计算

/// 时光机通知 ID。对应源端 `NOTIFY_CONSTANTS.TIMEMACHINE_BASE_ID + month * 100 + day`。
///
/// - Parameters:
///   - month: 1–12
///   - day: 1–31
/// - Returns: 通知标识符（8000 + month×100 + day）
func timeMachineNotificationID(month: Int, day: Int) -> Int {
    8000 + month * 100 + day
}

// MARK: - 共享 Calendar（固定 UTC，保证跨环境可复现）

/// 固定使用 UTC Calendar，与 TimelineLogic 保持一致。
var utcCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    // “UTC” 标识符解析失败时回退 .gmt（同为零偏移时区，语义等价）。
    cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return cal
}

/// 宽松解析 ISO 8601 日期字符串（接受 "2024-06-15" 和 "2024-06-15T10:00:00" 两种格式）。
private func parseISODate(_ string: String) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                         .withColonSeparatorInTime, .withTimeZone]
    if let date = iso.date(from: string) { return date }
    // 尝试纯日期格式 "2024-06-15"
    let dateOnly = ISO8601DateFormatter()
    dateOnly.formatOptions = [.withFullDate, .withDashSeparatorInDate]
    return dateOnly.date(from: string)
}
