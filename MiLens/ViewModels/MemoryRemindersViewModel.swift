//  MemoryRemindersViewModel —— 回忆提醒中心数据编排层。
//
//  读取照片/宠物，投影到 RemindersLogic 纯逻辑，产出三段可展示状态：
//  今日命中（生日/成为家人的日子/里程碑/往日回忆）、即将到来的日子（全部倒计时）、
//  往日回忆行（复用 HomeMemoryLogic）。
//
//  作为系统推送通知（NotifyService）的应用内兜底回看：不依赖通知权限、不丢失。
//  与 HomeViewModel 同构：@Observable + Repository 注入 + now 参数化。

import Foundation
import MiLensKit
import Observation

// MARK: - 往日回忆展示项

/// 往日回忆行（含缩略图路径，供页面渲染）。
struct MemoryReminderItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let thumbnailPath: String
}

@MainActor
@Observable
final class MemoryRemindersViewModel {

    /// 今日命中提醒（无命中时为空，页面整段隐藏）。
    private(set) var todayItems: [TodayReminder] = []
    /// 全部即将到来的纪念日倒计时（按 daysUntil 升序）。
    private(set) var upcomingItems: [UpcomingReminder] = []
    /// 往日回忆行（复用 HomeMemoryLogic 选片，含缩略图路径）。
    private(set) var memoryItems: [MemoryReminderItem] = []

    private(set) var isLoading = true
    private(set) var loadError: String?

    private let photoRepository: any PhotoRepositoryProtocol
    private let petRepository: any PetRepositoryProtocol
    private let now: () -> Date

    init(
        photoRepository: any PhotoRepositoryProtocol,
        petRepository: any PetRepositoryProtocol,
        now: @escaping () -> Date = Date.init
    ) {
        self.photoRepository = photoRepository
        self.petRepository = petRepository
        self.now = now
    }

    /// 今日是否有值得看的回忆（驱动首页铃铛摇晃动效）。
    var hasTodayContent: Bool {
        !todayItems.isEmpty
    }

    /// 页面是否完全为空（无今日、无倒计时、无回忆）。
    var isEmpty: Bool {
        todayItems.isEmpty && upcomingItems.isEmpty && memoryItems.isEmpty
    }

    func load() {
        isLoading = true
        loadError = nil

        do {
            let photos = try photoRepository.getPhotosPage(offset: 0, limit: 500)
            let pets = try petRepository.getAllPets()
            let now = now()

            // 投影到纯逻辑类型
            let reminderPets = pets.map { pet in
                ReminderPet(
                    id: pet.id,
                    name: pet.name,
                    birthday: pet.birthday,
                    adoptionDay: pet.adoptionDay,
                    events: pet.events
                        .filter { $0.sourceType != "user" }
                        .map { ReminderEvent(id: $0.id, title: $0.title, eventDate: $0.eventDate) }
                )
            }
            let reminderPhotos = photos.map {
                ReminderPhoto(
                    id: $0.id,
                    takenAt: $0.takenAt,
                    note: $0.note,
                    petID: $0.pet?.id,
                    thumbnailPath: $0.thumbnailPath.isEmpty ? $0.uri : $0.thumbnailPath
                )
            }

            // 今日命中
            todayItems = RemindersLogic.todayReminders(
                pets: reminderPets,
                photos: reminderPhotos,
                now: now,
                birthdayTitle: { name in
                    String(localized: "reminders.today.birthday \(name)")
                },
                adoptionTitle: { name in
                    String(localized: "reminders.today.adoption \(name)")
                },
                milestoneTitle: { name, days in
                    String(localized: "reminders.today.milestone \(name) \(days)")
                },
                memoryTitle: { yearsAgo in
                    String(localized: "reminders.today.memory \(yearsAgo)")
                }
            )

            // 全部倒计时
            upcomingItems = RemindersLogic.upcomingReminders(
                pets: reminderPets,
                now: now,
                birthdayTitle: { name in
                    String(localized: "home.upcoming.birthday \(name)")
                },
                adoptionTitle: { name in
                    String(localized: "home.upcoming.adoption \(name)")
                }
            )

            // 往日回忆（复用 HomeMemoryLogic，组装缩略图）
            let photoProjections = photos.map {
                HomeMemoryPhoto(id: $0.id, takenAt: $0.takenAt, note: $0.note, petID: $0.pet?.id)
            }
            let petProjections = pets.map { HomeMemoryPet(id: $0.id, name: $0.name) }
            let entries = HomeMemoryLogic.selectMemoryPhotos(
                photoProjections,
                now: now,
                pets: petProjections,
                sameDayTitle: { yearsAgo in
                    String(localized: "home.memory.yearsAgo \(yearsAgo)")
                },
                fallbackTitle: String(localized: "home.memoryTitle"),
                dateText: { date in
                    date.formatted(.dateTime.year().month().day())
                },
                datePetText: { dateText, petName in
                    String(localized: "home.memory.datePet \(dateText) \(petName)")
                }
            )
            memoryItems = entries.compactMap { entry in
                guard let photo = photos.first(where: { $0.id == entry.photoID }) else { return nil }
                return MemoryReminderItem(
                    id: entry.photoID,
                    title: entry.title,
                    subtitle: entry.subtitle,
                    thumbnailPath: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
                )
            }
        } catch {
            todayItems = []
            upcomingItems = []
            memoryItems = []
            loadError = String(localized: "reminders.loadError")
        }

        isLoading = false
    }
}
