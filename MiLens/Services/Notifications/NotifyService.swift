//  NotifyService —— 纪念提醒每日检查编排（对应源端 services/NotifyScheduler.ets + TimeMachineService.ets）。
//  每日检查：纪念日事件通知（同日拍摄、有备注的照片）+ 时光机（历史同日照片随机一张）。
//  同一天只执行一次（UserDefaults 日期标记去重，对应源端 WorkScheduler 每日触发语义）。
//  决策逻辑下沉为纯函数（NotifyCheckLogic / AnniversaryLogic / TimeMachineLogic），
//  本服务只做 IO：查照片、查宠物、请求授权、发布/撤销通知（DESIGN.md §4）。

import Foundation

@MainActor
final class NotifyService {

    /// 时光机通知标识符前缀（撤销时用于区分）。
    static let timeMachineIdentifierPrefix = "tm-"

    private let photoRepo: any PhotoRepositoryProtocol
    private let petRepo: any PetRepositoryProtocol
    private let poster: any NotificationPosting
    private let defaults: UserDefaults
    /// 随机源（时光机选片/文案模板，测试注入固定种子）
    private let randomSource: () -> Int

    init(
        photoRepo: any PhotoRepositoryProtocol,
        petRepo: any PetRepositoryProtocol,
        poster: any NotificationPosting,
        defaults: UserDefaults = .standard,
        randomSource: @escaping () -> Int = { Int.random(in: 0..<Int.max) }
    ) {
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.poster = poster
        self.defaults = defaults
        self.randomSource = randomSource
    }

    // MARK: - 每日检查

    /// 每日检查：纪念日 + 时光机。同一天只执行一次。
    /// - Parameters:
    ///   - now: 当前时间（注入保证测试可复现）
    ///   - calendar: 日历（默认当地时区）
    func runDailyCheck(now: Date = Date(), calendar: Calendar = .current) async {
        let lastCheckDate = defaults.object(forKey: NotifyCheckLogic.lastCheckDateKey) as? Date
        guard NotifyCheckLogic.shouldRunDailyCheck(
            lastCheckDate: lastCheckDate, now: now, calendar: calendar
        ) else { return }

        // 请求授权；拒绝时也标记当日，避免每次激活都弹系统窗（拒绝后系统不再弹）。
        guard await poster.requestAuthorization() else {
            markChecked(now: now)
            return
        }

        await checkAnniversaryEvents(now: now, calendar: calendar)
        await checkTimeMachine(now: now, calendar: calendar)
        markChecked(now: now)
    }

    /// 撤销全部已发布的纪念/时光机通知（设置开关关闭时调用）。
    func cancelAllNotifications() async {
        await poster.removeAllNotifications()
    }

    // MARK: - 纪念日事件通知

    private func checkAnniversaryEvents(now: Date, calendar: Calendar) async {
        let comp = calendar.dateComponents([.year, .month, .day], from: now)
        guard let month = comp.month, let day = comp.day else { return }

        guard let photos = try? photoRepo.getAnniversaryPhotos(
            month: month, day: day, excludeYear: nil
        ), !photos.isEmpty else { return }

        let projections = photos.map { TimeMachinePhoto(
            id: $0.id, takenAt: $0.takenAt, note: $0.note, petID: $0.pet?.id
        ) }
        for data in buildAnniversaryNotifications(photos: projections, now: now) {
            // identifier 用照片 UUID（稳定，可撤销）；源端用数字 photo.id。
            await poster.post(
                title: data.title, body: data.body, identifier: data.photoID.uuidString
            )
        }
    }

    // MARK: - 时光机（历史同日照片随机一张）

    private func checkTimeMachine(now: Date, calendar: Calendar) async {
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
        // identifier 带前缀，与纪念日通知区分（源端用 TIMEMACHINE_BASE_ID + 月日）。
        await poster.post(
            title: data.title, body: data.body,
            identifier: Self.timeMachineIdentifierPrefix + "\(data.identifier)"
        )
    }

    // MARK: - 当日标记

    private func markChecked(now: Date) {
        defaults.set(now, forKey: NotifyCheckLogic.lastCheckDateKey)
    }
}
