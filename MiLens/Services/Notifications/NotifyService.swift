//  NotifyService —— 纪念提醒调度编排（对应源端 services/NotifyScheduler.ets + TimeMachineService.ets）。
//
//  P1 重构：前台每日检查 → UNCalendarNotificationTrigger 真调度 + 幂等重调度。
//  - rescheduleAllReminders()：先 removeAllNotifications 再按当前数据全量调度
//    （宠物生日/领养日 → 年度重复通知；时光机 → 每日通知），调用方可反复执行。
//  - updateReminders(for:)/removeReminders(for:)：宠物编辑/删除后的局部更新。
//  决策逻辑下沉为纯函数（AnniversaryLogic / TimeMachineLogic），本服务只做 IO：
//  查照片、查宠物、调度/撤销通知（DESIGN.md §4）。

import Foundation

@MainActor
final class NotifyService {

    /// 时光机每日通知标识符（固定——重调度覆盖内容，撤销按此定位）。
    static let timeMachineIdentifier = "tm-daily"
    /// 宠物纪念日通知标识符前缀：`anniversary-<petID>-birthday|adoption`。
    static let anniversaryIdentifierPrefix = "anniversary-"
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
        await scheduleTimeMachine(now: now, calendar: calendar)
    }

    // MARK: - 宠物局部更新

    /// 宠物生日/领养日编辑后局部更新：撤销旧通知 + 按当前数据重调度。
    func updateReminders(for pet: Pet, calendar: Calendar = .current) async {
        await removeReminders(for: pet)
        await schedulePetAnniversaries(pets: [pet], calendar: calendar)
    }

    /// 宠物删除后撤销其纪念通知（不重调度）。
    func removeReminders(for pet: Pet) async {
        await poster.removeNotifications(identifiers: Self.anniversaryIdentifiers(for: pet))
    }

    /// 撤销全部已调度的纪念/时光机通知（设置开关关闭时调用）。
    func cancelAllNotifications() async {
        await poster.removeAllNotifications()
    }

    // MARK: - 宠物纪念日（年度重复，月日组件 + 固定 09:00）

    private func schedulePetAnniversaries(pets: [Pet]?, calendar: Calendar) async {
        let pets = pets ?? ((try? petRepo.getAllPets()) ?? [])
        for pet in pets {
            if let birthday = pet.birthday {
                await scheduleAnniversary(pet: pet, kind: .birthday, date: birthday, calendar: calendar)
            }
            if let adoptionDay = pet.adoptionDay {
                await scheduleAnniversary(pet: pet, kind: .adoption, date: adoptionDay, calendar: calendar)
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

        // 文案复用 AnniversaryLogic：以生日/领养日当天为「现在」→ "今天的回忆：<note>"
        let note = kind.notificationNote(petName: pet.name)
        guard let data = buildAnniversaryNotifications(
            photos: [TimeMachinePhoto(
                id: pet.id, takenAt: date, note: note, petID: pet.id
            )],
            now: date
        ).first else { return }

        // 单条调度失败静默（通知非关键路径，不阻断其余提醒）
        try? await poster.schedule(
            title: data.title, body: data.body,
            identifier: Self.anniversaryIdentifier(for: pet, kind: kind),
            dateComponents: trigger, repeats: true
        )
    }

    // MARK: - 时光机（每日 09:00，调度时固定当日选片）

    private func scheduleTimeMachine(now: Date, calendar: Calendar) async {
        let comp = calendar.dateComponents([.year, .month, .day], from: now)
        guard let month = comp.month, let day = comp.day, let year = comp.year else { return }

        // SQL 层排除当年（对应源端 getAnniversaryEvents 的 excludeYear），
        // 内存再校验一次历史照片（对应源端 historicalPhotos filter）。
        guard let photos = try? photoRepo.getAnniversaryPhotos(
            month: month, day: day, excludeYear: year
        ), !photos.isEmpty else { return }

        let projections = photos
            .filter { isHistoricalPhoto(takenAt: $0.takenAt, now: now) }
            .map { TimeMachinePhoto(
                id: $0.id, takenAt: $0.takenAt, note: $0.note, petID: $0.pet?.id
            ) }
        guard let selected = selectTimeMachinePhoto(
            projections, randomIndex: randomSource()
        ) else { return }

        let pets = ((try? petRepo.getAllPets()) ?? []).map {
            TimeMachinePet(id: $0.id, name: $0.name)
        }
        let data = buildTimeMachineResult(
            photo: selected, pets: pets, now: now, templateIndex: randomSource()
        )

        // 每日 09:00 重复；内容在调度时固定，下次 reschedule 刷新
        var trigger = DateComponents()
        trigger.hour = Self.reminderHour
        trigger.minute = Self.reminderMinute
        try? await poster.schedule(
            title: data.title, body: data.body,
            identifier: Self.timeMachineIdentifier,
            dateComponents: trigger, repeats: true
        )
    }

    // MARK: - 标识符

    static func anniversaryIdentifier(for pet: Pet, kind: PetAnniversaryKind) -> String {
        "\(anniversaryIdentifierPrefix)\(pet.id.uuidString)-\(kind.rawValue)"
    }

    static func anniversaryIdentifiers(for pet: Pet) -> [String] {
        [anniversaryIdentifier(for: pet, kind: .birthday),
         anniversaryIdentifier(for: pet, kind: .adoption)]
    }
}

/// 宠物纪念日类型（决定通知标识符后缀与文案）。
enum PetAnniversaryKind: String {
    case birthday
    case adoption

    /// 纪念日通知的备注文案（经 AnniversaryLogic 拼入正文）。
    func notificationNote(petName: String) -> String {
        switch self {
        case .birthday: return "\(petName)的生日"
        case .adoption: return "\(petName)的领养纪念日"
        }
    }
}
