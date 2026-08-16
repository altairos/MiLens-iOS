//  PetFormLogic —— 宠物档案表单校验/格式化纯逻辑
//  （对应源端 viewmodels/PetFormViewModel.ets）。
//
//  从 PetEditPage 抽出的表单解析、格式化、校验逻辑，使其可在无 SwiftUI 环境下单测。
//  物种 Emoji 与彩蛋常量复用 PetProfileLogic（源端在 PetFormViewModel/PetProfileViewModel
//  两处重复定义，iOS 端收敛到 PetProfileLogic 单一来源）。
//
//  架构差异：源端 birthday 为 ISO 字符串 + DatePickerResult 回调对象；
//  iOS Pet 存 Date? 且 SwiftUI DatePicker 直接产出 Date，故去掉
//  formatDatePickerResult/resolveInitialDate 的字符串往返，仅保留 resolveInitialDate
//  的「空值回退到默认日期」语义。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 常量

enum PetFormConstants {
    /// 单条重要事件备注的最大长度（对应源端 MAX_NOTE_ITEM_LENGTH）
    static let maxNoteItemLength = 25
    /// 视觉特征注册照片下限（对应源端 MIN_REGISTRATION_PHOTOS）
    static let minRegistrationPhotos = 8
    /// 视觉特征注册照片上限（对应源端 MAX_REGISTRATION_PHOTOS）
    static let maxRegistrationPhotos = 15
}

// MARK: - 表单状态

/// 宠物编辑表单状态（对应源端 PetFormState，与 PetEditView @State 一一对应）。
struct PetFormState: Equatable, Sendable {
    var name: String
    var species: Species
    var gender: Gender
    var birthday: Date?
    var adoptionDay: Date?
    var noteItems: [String]

    /// 创建默认的空表单状态（对应源端 defaultPetFormState）。
    static let empty = PetFormState(
        name: "", species: .unknown, gender: .unknown,
        birthday: nil, adoptionDay: nil, noteItems: []
    )
}

// MARK: - 备注条目解析/格式化

enum PetFormLogic {

    // ─── 备注条目 ───

    /// 将存储的 notes 字符串解析为备注条目数组（对应源端 parseNoteItems）。
    /// 每行去除前缀符号（· • - *）并 trim，过滤空行。
    static func parseNoteItems(_ notes: String) -> [String] {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        return trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                var s = String(line)
                // 去除前缀符号 · • - * 及其后空白
                if let first = s.first {
                    if "·•-*".contains(first) {
                        s.removeFirst()
                        s = s.trimmingCharacters(in: .whitespaces)
                    } else {
                        s = s.trimmingCharacters(in: .whitespaces)
                    }
                }
                return s.isEmpty ? nil : s
            }
    }

    /// 将备注条目数组格式化为存储字符串（每行加 "· " 前缀，对应源端 formatNoteItems）。
    static func formatNoteItems(_ items: [String]) -> String {
        items.map { "· \($0)" }.joined(separator: "\n")
    }

    /// 校验备注条目长度，返回超长项的错误消息或 nil（对应源端 validateNoteItemLength）。
    static func validateNoteItemLength(
        _ items: [String], maxLen: Int = PetFormConstants.maxNoteItemLength,
        locale: Locale = .current
    ) -> String? {
        for item in items {
            if item.count > maxLen {
                return String(localized: "pet.edit.note.tooLongToSave \(maxLen)", locale: locale)
            }
        }
        return nil
    }

    // ─── 彩蛋判定（复用 PetProfileLogic 常量）───

    /// 判断日期是否为彩蛋日期（7 月 3 日，对应源端 isEasterDate）。
    static func isEasterDate(_ date: Date?, calendar: Calendar = PetDateCalendar.gregorian) -> Bool {
        PetProfileLogic.shouldShowEasterEgg(monthDay: PetProfileLogic.monthDayString(from: date, calendar: calendar))
    }

    /// 判断生日是否从非彩蛋日期变为彩蛋日期（对应源端 hasBirthdayChanged）。
    static func hasBirthdayChanged(
        previous: Date?, current: Date?,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> Bool {
        !isEasterDate(previous, calendar: calendar) && isEasterDate(current, calendar: calendar)
    }

    // ─── 日期回退（对应源端 resolveInitialDate 的空值语义）───

    /// 解析初始日期：有效则原样返回，nil 则回退到 fallback（对应源端 resolveInitialDate）。
    /// iOS DatePicker 直接产出 Date，无需字符串往返。
    static func resolveInitialDate(_ date: Date?, fallback: Date = Date()) -> Date {
        date ?? fallback
    }

    // ─── 物种 Emoji（委托 PetProfileLogic）───

    static func speciesEmoji(_ species: Species) -> String {
        PetProfileLogic.speciesEmoji(species)
    }

    // ─── 表单未保存判定 ───

    /// 用于 hasUnsavedChanges 的比较快照（对应源端 PetComparisonSnapshot）。
    struct PetComparisonSnapshot: Equatable, Sendable {
        var name: String
        var species: Species
        var gender: Gender
        var birthday: Date?
        var adoptionDay: Date?
        var notes: String
        var avatarPath: String
    }

    /// 比较当前编辑状态与原始快照，判断是否有未保存修改（对应源端 hasUnsavedChanges）。
    static func hasUnsavedChanges(current: PetComparisonSnapshot, original: PetComparisonSnapshot) -> Bool {
        current != original
    }

    // ─── 备忘条目构建校验 ───

    /// validateAndBuildNoteItem 返回结果（对应源端 NoteItemValidationResult）。
    struct NoteItemValidationResult: Equatable {
        var ok: Bool
        var item: String
        var error: String

        static let rejectedEmpty = NoteItemValidationResult(ok: false, item: "", error: "")
    }

    /// 校验并构建备忘条目（对应源端 validateAndBuildNoteItem）。
    /// 空输入静默拒绝（ok=false, error=""）；超长拒绝并带错误文案。
    static func validateAndBuildNoteItem(
        _ input: String, maxLen: Int = PetFormConstants.maxNoteItemLength,
        locale: Locale = .current
    ) -> NoteItemValidationResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .rejectedEmpty }
        if trimmed.count > maxLen {
            return NoteItemValidationResult(
                ok: false, item: "",
                error: String(localized: "pet.edit.note.tooLong \(maxLen)", locale: locale))
        }
        return NoteItemValidationResult(ok: true, item: trimmed, error: "")
    }

    // ─── 视觉特征注册常量与校验 ───

    /// 计算剩余可选照片数（对应源端 resolveMaxSelectNumber）。
    static func resolveMaxSelectNumber(currentCount: Int) -> Int {
        max(0, PetFormConstants.maxRegistrationPhotos - currentCount)
    }

    /// 注册照片文件名构造（对应源端 buildRegPhotoFileName，iOS 用 UUID）。
    static func buildRegPhotoFileName(petID: UUID, index: Int, timestamp: Date = Date()) -> String {
        let ts = Int(timestamp.timeIntervalSince1970 * 1000)
        return "pet_\(petID.uuidString)_\(ts)_\(index).jpg"
    }

    /// 格式化注册进度提示文案（对应源端 formatRegistrationProgress）。
    static func formatRegistrationProgress(count: Int) -> String {
        "正在提取特征 (\(count) 张照片)..."
    }

    /// 根据照片数量校验是否可注册（对应源端 resolveRegistrationValidation）。
    /// 返回空串表示通过，否则返回错误文案。
    static func resolveRegistrationValidation(uris: [String]) -> String {
        if uris.count < PetFormConstants.minRegistrationPhotos { return "请至少选择 8 张照片" }
        return ""
    }
}
