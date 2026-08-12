//  NotifyService —— 纪念提醒调度编排（对应源端 services/NotifyScheduler.ets + TimeMachineService.ets）。
//
//  P1 重构：前台每日检查 → UNCalendarNotificationTrigger 真调度 + 幂等重调度。
//  - rescheduleAllReminders()：先 removeAllNotifications 再按当前数据全量调度
//    （生日/成为家人的日子 → 年度重复通知；里程碑/时光机 → 单次通知），
//    调用方可反复执行。
//  - updateReminders(for:)/removeReminders(for:)：宠物编辑/删除后的局部更新。
//  决策逻辑下沉为纯函数（AnniversaryLogic / TimeMachineLogic），本服务只做 IO：
//  查照片、查宠物、调度/撤销通知（DESIGN.md §4）。

import Foundation
import MiLensKit
import os

@MainActor
final class NotifyService {

    private let logger = Logger(subsystem: "com.milens.app", category: "Notify")

    /// 时光机预排窗口天数：每天一条**单次**通知（内容按当天选片生成），
    /// App 每次激活/重调度刷新窗口。不用固定内容的 repeating trigger——
    /// 否则用户多日不打开 App 时，每天收到的仍是首次调度时的过期选片与文案。
    static let timeMachineWindowDays = 7
    /// 时光机通知标识符前缀：`tm-daily-<yyyyMMdd>`（每天一条，撤销/覆盖按标识符定位）。
    static let timeMachineIdentifierPrefix = "tm-daily"
    /// 宠物周年通知标识符前缀：`anniversary-<petID>-birthday|adoption`。
    static let anniversaryIdentifierPrefix = "anniversary-"
    /// 相处里程碑通知标识符前缀：`milestone-<petID>-<days>`。
    static let milestoneIdentifierPrefix = "milestone-"
    /// 提醒触发时间（固定 09:00，P1 不引入可配置时间 UI）。
    static let reminderHour = 9
    static let reminderMinute = 0

    private let photoRepo: any PhotoRepositoryProtocol
    private let petRepo: any PetRepositoryProtocol
    private let poster: any NotificationPosting
    /// 随机源（时光机选片/文案模板，测试注入固定种子）
    private let randomSource: () -> Int

    init(
        photoRepo: any PhotoRepositoryProtocol,
        petRepo: any PetRepositoryProtocol,
        poster: any NotificationPosting,
        randomSource: @escaping () -> Int = { Int.random(in: 0..<Int.max) }
    ) {
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.poster = poster
        self.randomSource = randomSource
    }

    // MARK: - 授权（设置开关路径用；调度本身不请求授权）

    /// 请求通知授权（系统弹窗）。返回当前是否已授权。
    func requestAuthorization() async -> Bool {
        await poster.requestAuthorization()
    }

    /// 当前授权状态。
    func authorizationStatus() async -> Bool {
        await poster.authorizationStatus()
    }

    // MARK: - 全量重调度（幂等）

    /// 全量重调度所有纪念提醒（幂等：先清空再按数据调度）。
    /// 设置开关打开 / App 激活（开关开启时）调用；不请求授权（授权由开关路径保证）。
    /// - Parameters:
    ///   - now: 当前时间（时光机选片基准，注入保证测试可复现）
    ///   - calendar: 日历（默认当地时区）
    func rescheduleAllReminders(now: Date = Date(), calendar: Calendar = .current) async {
        await poster.removeAllNotifications()
        await schedulePetAnniversaries(pets: nil, calendar: calendar)
        await schedulePetMilestones(pets: nil, now: now, calendar: calendar)
        await scheduleTimeMachine(now: now, calendar: calendar)
    }

    // MARK: - 宠物局部更新

    /// 宠物日期编辑后局部更新：撤销旧通知 + 按当前数据重调度。
    func updateReminders(for pet: Pet, now: Date = Date(), calendar: Calendar = .current) async {
        await removeReminders(for: pet)
        await schedulePetAnniversaries(pets: [pet], calendar: calendar)
        await schedulePetMilestones(pets: [pet], now: now, calendar: calendar)
    }

    /// 宠物删除后撤销其周年与里程碑通知（不重调度）。
    func removeReminders(for pet: Pet) async {
        await poster.removeNotifications(identifiers: Self.reminderIdentifiers(for: pet))
    }

    /// 撤销全部已调度的纪念/时光机通知（设置开关关闭时调用）。
    func cancelAllNotifications() async {
        await poster.removeAllNotifications()
    }

    // MARK: - 宠物纪念日（年度重复，月日组件 + 固定 09:00）

    private func schedulePetAnniversaries(pets providedPets: [Pet]?, calendar: Calendar) async {
        let pets: [Pet]
        if let providedPets {
            pets = providedPets
        } else {
            do {
                pets = try petRepo.getAllPets()
            } catch {
                logger.error("schedulePetAnniversaries: 读取宠物列表失败（\(error.localizedDescription)），跳过宠物纪念通知")
                pets = []
            }
        }
        for pet in pets {
            if let birthday = pet.birthday {
                await scheduleAnniversary(pet: pet, kind: .birthday, date: birthday, calendar: calendar)
            }
            if let adoptionDay = pet.adoptionDay {
                await scheduleAnniversary(pet: pet, kind: .adoption, date: adoptionDay, calendar: calendar)
            }
        }
    }

    // MARK: - 相处里程碑（按日期单次触发）

    private func schedulePetMilestones(
        pets providedPets: [Pet]?, now: Date, calendar: Calendar
    ) async {
        let pets: [Pet]
        if let providedPets {
            pets = providedPets
        } else {
            do {
                pets = try petRepo.getAllPets()
            } catch {
                logger.error("schedulePetMilestones: 读取宠物列表失败（\(error.localizedDescription)），跳过里程碑通知")
                pets = []
            }
        }

        for pet in pets {
            guard let adoptionDay = pet.adoptionDay, adoptionDay <= now else { continue }
            for days in MilestoneLogic.milestoneDays {
                let milestoneDate = MilestoneLogic.milestoneDate(anchor: adoptionDay, days: days)
                var trigger = calendar.dateComponents([.year, .month, .day], from: milestoneDate)
                trigger.hour = Self.reminderHour
                trigger.minute = Self.reminderMinute
                guard let fireDate = calendar.date(from: trigger), fireDate > now else { continue }

                let copy = buildPetMilestoneNotification(petName: pet.name, days: days)
                do {
                    try await poster.schedule(
                        title: copy.title,
                        body: copy.body,
                        identifier: Self.milestoneIdentifier(for: pet, days: days),
                        dateComponents: trigger,
                        repeats: false
                    )
                } catch {
                    logger.error("schedulePetMilestones: 调度失败（\(pet.name)，第\(days)天，\(error.localizedDescription)）")
                }
            }
        }
    }

    private func scheduleAnniversary(
        pet: Pet, kind: PetAnniversaryKind, date: Date, calendar: Calendar
    ) async {
        let comp = calendar.dateComponents([.month, .day], from: date)
        guard let month = comp.month, let day = comp.day else { return }

        // 月日 + 固定 09:00；无年份 → UNCalendarNotificationTrigger 每年重复
        var trigger = DateComponents()
        trigger.month = month
        trigger.day = day
        trigger.hour = Self.reminderHour
        trigger.minute = Self.reminderMinute

        let copy = buildPetAnniversaryNotification(petName: pet.name, kind: kind)

        // 单条调度失败不阻断其余提醒（通知非关键路径），但记录错误便于诊断
        do {
            try await poster.schedule(
                title: copy.title, body: copy.body,
                identifier: Self.anniversaryIdentifier(for: pet, kind: kind),
                dateComponents: trigger, repeats: true
            )
        } catch {
            logger.error("scheduleAnniversary: 调度失败（\(pet.name)，\(error.localizedDescription)）")
        }
    }

    // MARK: - 时光机（预排未来 N 天，每天 09:00 单次通知，内容按当天选片）

    /// 预排未来 timeMachineWindowDays 天的单次通知。
    /// 每天一条独立标识符 + 独立内容（标题「N年前的今天」按当天日期计算）；
    /// 当天触发时刻已过 → 跳过当天；当天无历史照片 → 不调度。
    /// 窗口每天刷新（App 激活时 rescheduleAllReminders），避免固定内容的每日重复。
    private func scheduleTimeMachine(now: Date, calendar: Calendar) async {
        let startOfDay = calendar.startOfDay(for: now)
        for offset in 0..<Self.timeMachineWindowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay) else { continue }
            // 单次触发时刻（当天 09:00）已过 → 跳过（今天的内容不再送达）
            var trigger = calendar.dateComponents([.year, .month, .day], from: day)
            trigger.hour = Self.reminderHour
            trigger.minute = Self.reminderMinute
            guard let fireDate = calendar.date(from: trigger), fireDate > now else { continue }
            await scheduleTimeMachineDay(day: day, now: fireDate, calendar: calendar)
        }
    }

    /// 调度某一天的单次时光机通知（选片/文案以当天为「现在」计算）。
    private func scheduleTimeMachineDay(day: Date, now: Date, calendar: Calendar) async {
        let comp = calendar.dateComponents([.year, .month, .day], from: day)
        guard let month = comp.month, let dayOfMonth = comp.day, let year = comp.year else { return }

        // 单次触发时刻：当天 09:00（含年月日 → 不重复）
        var trigger = calendar.dateComponents([.year, .month, .day], from: day)
        trigger.hour = Self.reminderHour
        trigger.minute = Self.reminderMinute

        // SQL 层排除当年（对应源端 getAnniversaryEvents 的 excludeYear），
        // 内存再校验一次历史照片（对应源端 historicalPhotos filter）。
        let photos: [Photo]
        do {
            photos = try photoRepo.getAnniversaryPhotos(
                month: month, day: dayOfMonth, excludeYear: year
            )
        } catch {
            logger.error("scheduleTimeMachine: 读取纪念照片失败（\(error.localizedDescription)），跳过当天时光机")
            return
        }
        guard !photos.isEmpty else { return }

        let projections = photos
            .filter { isHistoricalPhoto(takenAt: $0.takenAt, now: now) }
            .map { TimeMachinePhoto(
                id: $0.id, takenAt: $0.takenAt, note: $0.note, petID: $0.pet?.id
            ) }
        guard let selected = selectTimeMachinePhoto(
            projections, randomIndex: randomSource()
        ) else { return }

        let pets: [Pet]
        do {
            pets = try petRepo.getAllPets()
        } catch {
            logger.error("scheduleTimeMachine: 读取宠物列表失败（\(error.localizedDescription)），时光机通知不带宠物名")
            pets = []
        }
        let petProjections = pets.map {
            TimeMachinePet(id: $0.id, name: $0.name)
        }
        let data = buildTimeMachineResult(
            photo: selected, pets: petProjections, now: now, templateIndex: randomSource()
        )

        // 单次通知（repeats = false）：每天一条独立标识符；单条失败不阻断其余日期
        do {
            try await poster.schedule(
                title: data.title, body: data.body,
                identifier: Self.timeMachineIdentifier(for: day, calendar: calendar),
                dateComponents: trigger, repeats: false
            )
        } catch {
            logger.error("scheduleTimeMachine: 调度失败（\(error.localizedDescription)）")
        }
    }

    // MARK: - 标识符

    /// 时光机通知标识符：`tm-daily-<yyyyMMdd>`（按调度日生成，稳定可撤销）。
    static func timeMachineIdentifier(for day: Date, calendar: Calendar = .current) -> String {
        let comp = calendar.dateComponents([.year, .month, .day], from: day)
        let year = comp.year ?? 0
        let month = comp.month ?? 0
        let dayOfMonth = comp.day ?? 0
        return "\(timeMachineIdentifierPrefix)-\(String(format: "%04d%02d%02d", year, month, dayOfMonth))"
    }

    static func anniversaryIdentifier(for pet: Pet, kind: PetAnniversaryKind) -> String {
        "\(anniversaryIdentifierPrefix)\(pet.id.uuidString)-\(kind.rawValue)"
    }

    static func anniversaryIdentifiers(for pet: Pet) -> [String] {
        [anniversaryIdentifier(for: pet, kind: .birthday),
         anniversaryIdentifier(for: pet, kind: .adoption)]
    }

    static func milestoneIdentifier(for pet: Pet, days: Int) -> String {
        "\(milestoneIdentifierPrefix)\(pet.id.uuidString)-\(days)"
    }

    static func milestoneIdentifiers(for pet: Pet) -> [String] {
        MilestoneLogic.milestoneDays.map { milestoneIdentifier(for: pet, days: $0) }
    }

    static func reminderIdentifiers(for pet: Pet) -> [String] {
        anniversaryIdentifiers(for: pet) + milestoneIdentifiers(for: pet)
    }
}

/// 宠物纪念日类型（决定通知标识符后缀与文案）。
enum PetAnniversaryKind: String {
    case birthday
    case adoption

}
