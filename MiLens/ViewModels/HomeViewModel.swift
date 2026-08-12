//  HomeViewModel —— 首页数据编排层。
//
//  首页视觉只消费这个快照，不直接拼装 SwiftData 查询。选片、问候和回忆
//  规则由 MiLensKit 纯逻辑负责；本层只做仓储读取、实体投影和可展示状态。

import Foundation
import MiLensKit
import Observation

@MainActor
@Observable
final class HomeViewModel {
    struct MemoryItem: Identifiable {
        let id: UUID
        let entry: HomeMemoryEntry
        let photo: Photo
    }

    /// 即将到来的纪念日（对照 Figma #319:1039-1044「即将到来的日子」）。
    struct UpcomingDay: Identifiable {
        /// 纪念日来源类型，决定「已陪伴天数」的文案语义。
        enum Kind: Sendable {
            /// 生日：daysTogether 语义 = 「出生至今 N 天」
            case birthday
            /// 领养日：daysTogether 语义 = 「已陪伴 N 天」
            case adoption
            /// 其他纪念事件：daysTogether 语义 = 「已记录 N 天」
            case memorial
        }

        let id: UUID
        /// 纪念日标题（「第一次见面的日子」/「小满的生日」）。
        let title: String
        let petName: String
        /// 关联宠物 ID（点击进档案）。
        let petID: UUID
        /// 纪念日今年/明年的下一次发生日期。
        let nextDate: Date
        /// 距今天数（≥0）。
        let daysUntil: Int
        /// 从原始日期到现在的天数（语义随 kind 变化）。
        let daysTogether: Int
        /// 纪念日来源类型。
        let kind: Kind
        /// 代表照片缩略图（可选，展示在右侧）。
        let thumbnailPath: String?
    }

    var photos: [Photo] = []
    var pets: [Pet] = []
    var memoryItems: [MemoryItem] = []
    var isLoading = true
    var loadError: String?

    private let photoRepository: any PhotoRepositoryProtocol
    private let petRepository: any PetRepositoryProtocol
    private let now: () -> Date
    /// hero 回退选片的随机种子；在 load() 时固定，避免计算属性每次重算都换一张。
    private var heroRandomIndex: Int = 0

    init(
        photoRepository: any PhotoRepositoryProtocol,
        petRepository: any PetRepositoryProtocol,
        now: @escaping () -> Date = Date.init
    ) {
        self.photoRepository = photoRepository
        self.petRepository = petRepository
        self.now = now
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: now())
        return HomeGreetingLogic.greeting(forHour: hour)
    }

    var heroPhoto: Photo? {
        let projections = photos.map {
            HomeHeroPhoto(id: $0.id, takenAt: $0.takenAt, petID: $0.pet?.id, qualityScore: $0.qualityScore)
        }
        guard let selected = HomeHeroLogic.selectHeroPhoto(projections, now: now(), randomIndex: heroRandomIndex) else {
            return nil
        }
        return photos.first { $0.id == selected.id }
    }

    var heroIsToday: Bool {
        guard let heroPhoto else { return false }
        return HomeHeroLogic.isToday(takenAt: heroPhoto.takenAt, now: now())
    }

    var heroCaption: String {
        HomeHeroLogic.buildHeroCaption(
            petName: heroPhoto?.pet?.name,
            isToday: heroIsToday
        )
    }

    /// 今日是否有值得看的回忆（驱动首页铃铛摇晃动效）。
    /// 复用 RemindersLogic 纯逻辑：生日/成为家人的日子/里程碑/往日回忆任一命中即为 true。
    var hasTodayContent: Bool {
        let reminderPets = pets.map { pet in
            ReminderPet(
                id: pet.id, name: pet.name,
                birthday: pet.birthday, adoptionDay: pet.adoptionDay,
                events: pet.events
                    .filter { $0.sourceType != "user" }
                    .map { ReminderEvent(id: $0.id, title: $0.title, eventDate: $0.eventDate) }
            )
        }
        let reminderPhotos = photos.map {
            ReminderPhoto(id: $0.id, takenAt: $0.takenAt, note: $0.note, petID: $0.pet?.id)
        }
        return !RemindersLogic.todayReminders(
            pets: reminderPets, photos: reminderPhotos, now: now()
        ).isEmpty
    }

    func load() {
        isLoading = true
        loadError = nil

        do {
            // 首页只需要最近一批照片，同时覆盖回忆区；不会把整个图库读入内存。
            photos = try photoRepository.getPhotosPage(offset: 0, limit: 500)
            pets = try petRepository.getAllPets()

            let photoProjections = photos.map {
                HomeMemoryPhoto(id: $0.id, takenAt: $0.takenAt, note: $0.note, petID: $0.pet?.id)
            }
            let petProjections = pets.map { HomeMemoryPet(id: $0.id, name: $0.name) }
            let entries = HomeMemoryLogic.selectMemoryPhotos(
                photoProjections,
                now: now(),
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
                return MemoryItem(id: entry.photoID, entry: entry, photo: photo)
            }
        } catch {
            photos = []
            pets = []
            memoryItems = []
            loadError = String(localized: "home.loadError")
        }

        // 固定本次加载的 hero 随机种子（≥1，避免空池模零；load 后不再变化，
        // 直到下次 load 才换一张，保证首页不会每次重绘都跳图）。
        heroRandomIndex = Int.random(in: 1...max(1, photos.count))

        isLoading = false
    }

    // MARK: - 即将到来的纪念日

    /// 下一个即将到来的纪念日（生日/领养日/PetEvent 中天数最近的）。
    /// 无有效日期时返回 nil。
    var upcomingDay: UpcomingDay? {
        let now = now()
        let cal = Calendar.current
        var candidates: [UpcomingDay] = []

        for pet in pets {
            // 生日
            if let birthday = pet.birthday {
                if let upcoming = buildUpcoming(
                    originalDate: birthday, title: String(localized: "home.upcoming.birthday \(pet.name)"),
                    petName: pet.name, petID: pet.id, kind: .birthday, now: now, cal: cal
                ) { candidates.append(upcoming) }
            }
            // 领养日
            if let adoption = pet.adoptionDay {
                if let upcoming = buildUpcoming(
                    originalDate: adoption, title: String(localized: "home.upcoming.adoption \(pet.name)"),
                    petName: pet.name, petID: pet.id, kind: .adoption, now: now, cal: cal
                ) { candidates.append(upcoming) }
            }
            // PetEvent（用户纪念事件）
            for ev in pet.events where ev.sourceType != "user" {
                if let upcoming = buildUpcoming(
                    originalDate: ev.eventDate, title: ev.title,
                    petName: pet.name, petID: pet.id, kind: .memorial, now: now, cal: cal
                ) { candidates.append(upcoming) }
            }
        }

        // 取天数最近的（跳过已过去的今天：daysUntil == 0 保留，负数不出现）
        return candidates.sorted { $0.daysUntil < $1.daysUntil }.first.map { upcoming in
            // 尝试找到一张代表照片
            let thumb = photos.first { $0.pet?.id == upcoming.petID }?.thumbnailPath
            return UpcomingDay(
                id: upcoming.id, title: upcoming.title, petName: upcoming.petName,
                petID: upcoming.petID, nextDate: upcoming.nextDate,
                daysUntil: upcoming.daysUntil, daysTogether: upcoming.daysTogether,
                kind: upcoming.kind,
                thumbnailPath: (thumb?.isEmpty == false) ? thumb : nil
            )
        }
    }

    /// 把原始日期推进到今年/明年的下一次月日匹配，构建候选 UpcomingDay。
    private func buildUpcoming(
        originalDate: Date, title: String, petName: String, petID: UUID,
        kind: UpcomingDay.Kind, now: Date, cal: Calendar
    ) -> UpcomingDay? {
        let comp = cal.dateComponents([.month, .day], from: originalDate)
        guard let month = comp.month, let day = comp.day else { return nil }

        // 今年
        let nowYear = cal.component(.year, from: now)
        var dc = DateComponents()
        dc.year = nowYear
        dc.month = month
        dc.day = day
        guard let thisYear = cal.date(from: dc) else { return nil }

        // 如果今年已过，取明年
        let target: Date
        if thisYear >= cal.startOfDay(for: now) {
            target = thisYear
        } else {
            dc.year = nowYear + 1
            target = cal.date(from: dc) ?? thisYear
        }

        let daysUntil = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: target)).day ?? 0)
        let daysTogether = max(0, cal.dateComponents([.day], from: originalDate, to: now).day ?? 0)

        return UpcomingDay(
            id: petID, title: title, petName: petName, petID: petID,
            nextDate: target, daysUntil: daysUntil, daysTogether: daysTogether,
            kind: kind, thumbnailPath: nil
        )
    }
}
