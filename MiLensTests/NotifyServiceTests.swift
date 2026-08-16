import XCTest
import MiLensKit
@testable import MiLens

/// NotifyService 调度编排测试——宠物纪念日年度重复 + 时光机每日、幂等重调度、
/// 宠物编辑/删除局部更新、开关撤销。
/// 使用纯内存 mock（不碰 SwiftData），与 OnboardingViewModelTests 同策略。
@MainActor
final class NotifyServiceTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// 构造服务：预置照片（note 非空、eventNotify 默认 true）。
    private func makeService(
        photos: [Photo] = [],
        pets: [Pet] = [],
        random: Int = 0
    ) -> (NotifyService, MockNotificationPoster, InMemoryPhotoRepository, InMemoryPetRepository) {
        let photoRepo = InMemoryPhotoRepository(photos: photos)
        let petRepo = InMemoryPetRepository(pets: pets)
        let poster = MockNotificationPoster()
        let service = NotifyService(
            photoRepo: photoRepo, petRepo: petRepo, poster: poster,
            randomSource: { random }
        )
        return (service, poster, photoRepo, petRepo)
    }

    private func photo(_ id: String, takenAt: Date?, note: String = "纪念日", pet: Pet? = nil) -> Photo {
        Photo(uri: id, pet: pet, takenAt: takenAt, note: note)
    }

    // MARK: - 宠物纪念日（年度重复）

    func testRescheduleSchedulesPetBirthdayAndAdoption() async {
        let pet = Pet(name: "小橘", birthday: date(2020, 5, 1), adoptionDay: date(2021, 6, 2))
        let (service, poster, _, _) = makeService(pets: [pet])

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        // 幂等：先清空再按数据调度
        XCTAssertEqual(poster.removeAllCount, 1)

        // 生日：anniversary-<petID>-birthday，5/1 09:00 每年重复
        let birthday = poster.scheduled.first {
            $0.identifier == NotifyService.anniversaryIdentifier(for: pet, kind: .birthday)
        }
        XCTAssertNotNil(birthday)
        XCTAssertEqual(birthday?.dateComponents.month, 5)
        XCTAssertEqual(birthday?.dateComponents.day, 1)
        XCTAssertEqual(birthday?.dateComponents.hour, NotifyService.reminderHour)
        XCTAssertEqual(birthday?.dateComponents.minute, NotifyService.reminderMinute)
        XCTAssertNil(birthday?.dateComponents.year, "无年份 = 每年重复")
        XCTAssertEqual(birthday?.repeats, true)

        // 成为家人的日子：anniversary-<petID>-adoption，6/2 09:00 每年重复
        let adoption = poster.scheduled.first {
            $0.identifier == NotifyService.anniversaryIdentifier(for: pet, kind: .adoption)
        }
        XCTAssertNotNil(adoption)
        XCTAssertEqual(adoption?.dateComponents.month, 6)
        XCTAssertEqual(adoption?.dateComponents.day, 2)
        XCTAssertEqual(adoption?.repeats, true)
    }

    func testPetWithoutAnniversaryDatesSchedulesNothing() async {
        let pet = Pet(name: "无纪念日")
        let (service, poster, _, _) = makeService(pets: [pet])

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        // 无纪念日宠物：不调度宠物相关纪念通知（备份/新照片提醒独立于宠物数据，由各自条件决定）
        XCTAssertTrue(poster.scheduled.filter {
            $0.identifier.hasPrefix(NotifyService.anniversaryIdentifierPrefix)
                || $0.identifier.hasPrefix(NotifyService.milestoneIdentifierPrefix)
        }.isEmpty)
    }

    func testBirthdayNotificationUsesPetSpecificTitleAndBody() async {
        let pet = Pet(name: "小橘", birthday: date(2020, 5, 1))
        let (service, poster, _, _) = makeService(pets: [pet])

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        let birthday = poster.scheduled.first {
            $0.identifier == NotifyService.anniversaryIdentifier(for: pet, kind: .birthday)
        }
        XCTAssertEqual(birthday?.title, "今天是小橘的生日")
        XCTAssertEqual(birthday?.body, "去看看小橘的生日回忆吧。")
    }

    func testAdoptionNotificationUsesFamilyDayWording() async {
        let pet = Pet(name: "小橘", adoptionDay: date(2021, 6, 2))
        let (service, poster, _, _) = makeService(pets: [pet])

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        let adoption = poster.scheduled.first {
            $0.identifier == NotifyService.anniversaryIdentifier(for: pet, kind: .adoption)
        }
        XCTAssertEqual(adoption?.title, "今天是和小橘成为家人的日子")
        XCTAssertEqual(adoption?.body, "去看看你们一起留下的回忆吧。")
    }

    func testUpcomingMilestoneSchedulesOneShotNotification() async {
        let adoptionDay = date(2026, 1, 1)
        let pet = Pet(name: "小橘", adoptionDay: adoptionDay)
        let now = date(2026, 3, 1)
        let (service, poster, _, _) = makeService(pets: [pet])

        await service.rescheduleAllReminders(now: now, calendar: calendar)

        let milestone = poster.scheduled.first {
            $0.identifier == NotifyService.milestoneIdentifier(for: pet, days: 100)
        }
        XCTAssertNotNil(milestone)
        XCTAssertEqual(milestone?.title, "来到家100天")
        XCTAssertEqual(milestone?.body, "小橘已经来到这个家100天了")
        var expectedDateComponents = calendar.dateComponents(
            [.year, .month, .day],
            from: MilestoneLogic.milestoneDate(anchor: adoptionDay, days: 100)
        )
        expectedDateComponents.hour = NotifyService.reminderHour
        expectedDateComponents.minute = NotifyService.reminderMinute
        XCTAssertEqual(milestone?.dateComponents, expectedDateComponents)
        XCTAssertFalse(milestone?.repeats ?? true)
    }

    // MARK: - 时光机（预排未来 N 天，每天 09:00 单次通知）

    func testRescheduleSchedulesTimeMachineWhenHistoricalPhotosExist() async {
        let photos = [photo("a", takenAt: date(2025, 8, 8), note: "A")]
        let (service, poster, _, _) = makeService(photos: photos)

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        // 8/8 有历史照片 → 预排当天单次通知（未来 7 天窗口内只有这天有照片）
        let tm = poster.scheduled.first {
            $0.identifier == NotifyService.timeMachineIdentifier(for: date(2026, 8, 8), calendar: calendar)
        }
        XCTAssertNotNil(tm)
        XCTAssertEqual(tm?.dateComponents.hour, NotifyService.reminderHour)
        XCTAssertEqual(tm?.dateComponents.minute, NotifyService.reminderMinute)
        XCTAssertEqual(tm?.dateComponents.month, 8)
        XCTAssertEqual(tm?.dateComponents.day, 8)
        XCTAssertEqual(tm?.dateComponents.year, 2026, "单次通知带年份（当天触发，不重复）")
        XCTAssertEqual(tm?.repeats, false, "时光机必须用单次通知，不能用固定内容的每日重复")
        XCTAssertEqual(tm?.title, "1年前的今天")

        // 窗口内其余日期无照片 → 不调度
        let tmTomorrow = poster.scheduled.first {
            $0.identifier == NotifyService.timeMachineIdentifier(for: date(2026, 8, 9), calendar: calendar)
        }
        XCTAssertNil(tmTomorrow)
    }

    func testTimeMachineWindowSchedulesEachDayWithOwnContent() async {
        // 两天各有历史照片：内容必须按各自日期生成（标题年份不同）
        let photos = [
            photo("a", takenAt: date(2025, 8, 8), note: "A"),
            photo("b", takenAt: date(2024, 8, 9), note: "B")
        ]
        let (service, poster, _, _) = makeService(photos: photos)

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        let tmDay1 = poster.scheduled.first {
            $0.identifier == NotifyService.timeMachineIdentifier(for: date(2026, 8, 8), calendar: calendar)
        }
        let tmDay2 = poster.scheduled.first {
            $0.identifier == NotifyService.timeMachineIdentifier(for: date(2026, 8, 9), calendar: calendar)
        }
        XCTAssertNotNil(tmDay1)
        XCTAssertNotNil(tmDay2)
        XCTAssertEqual(tmDay1?.title, "1年前的今天", "8/8 的照片按 8/8 计算年份差")
        XCTAssertEqual(tmDay2?.title, "2年前的今天", "8/9 的照片按 8/9 计算年份差")
        XCTAssertNotEqual(tmDay1?.identifier, tmDay2?.identifier, "每天独立标识符，可单独撤销/覆盖")
        XCTAssertEqual(tmDay1?.repeats, false)
        XCTAssertEqual(tmDay2?.repeats, false)
    }

    func testTimeMachineSkipsTodayWhenTriggerTimeAlreadyPassed() async {
        // now = 2026-08-08 10:00（已过 09:00）→ 当天不调度，但 8/9 仍正常预排
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 10))!
        let photos = [
            photo("a", takenAt: date(2025, 8, 8), note: "A"),
            photo("b", takenAt: date(2025, 8, 9), note: "B")
        ]
        let (service, poster, _, _) = makeService(photos: photos)

        await service.rescheduleAllReminders(now: now, calendar: calendar)

        let tmToday = poster.scheduled.first {
            $0.identifier == NotifyService.timeMachineIdentifier(for: date(2026, 8, 8), calendar: calendar)
        }
        XCTAssertNil(tmToday, "当天触发时刻已过：不得调度已过期的单次通知")
        let tmTomorrow = poster.scheduled.first {
            $0.identifier == NotifyService.timeMachineIdentifier(for: date(2026, 8, 9), calendar: calendar)
        }
        XCTAssertNotNil(tmTomorrow)
    }

    func testRescheduleSkipsTimeMachineWithoutHistoricalPhotos() async {
        // 只有今年今日的照片（时光机排除当年）→ 不调度任何时光机通知
        let photos = [photo("cur", takenAt: date(2026, 8, 8), note: "今年")]
        let (service, poster, _, _) = makeService(photos: photos)

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        XCTAssertTrue(poster.scheduled.filter {
            $0.identifier.hasPrefix(NotifyService.timeMachineIdentifierPrefix)
        }.isEmpty)
    }

    // MARK: - 幂等重调度

    func testRescheduleIsIdempotent() async {
        let pet = Pet(name: "小橘", birthday: date(2020, 5, 1))
        let (service, poster, _, _) = makeService(pets: [pet])

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)
        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        XCTAssertEqual(poster.removeAllCount, 2)
        // 同一 identifier 重复调度由系统覆盖（mock 追加记录）：宠物纪念 + 备份 + 新照片提醒，去重后各自唯一
        let identifiers = Set(poster.scheduled.map(\.identifier))
        XCTAssertTrue(identifiers.contains(NotifyService.anniversaryIdentifier(for: pet, kind: .birthday)))
        XCTAssertTrue(identifiers.contains(NotifyService.backupReminderIdentifier))
        XCTAssertTrue(identifiers.contains(NotifyService.newPhotoReminderIdentifier))
    }

    // MARK: - 宠物编辑/删除局部更新

    func testUpdateRemindersReschedulesPetAfterEdit() async {
        let pet = Pet(name: "小橘", birthday: date(2020, 5, 1))
        let (service, poster, _, _) = makeService(pets: [pet])

        // 编辑：生日改为 6/1
        pet.birthday = date(2020, 6, 1)
        await service.updateReminders(for: pet, calendar: calendar)

        // 先撤销周年与里程碑 identifier，再按新日期调度
        XCTAssertEqual(Set(poster.removedIdentifiers), Set(NotifyService.reminderIdentifiers(for: pet)))
        // 按新日期调度
        let birthday = poster.scheduled.first {
            $0.identifier == NotifyService.anniversaryIdentifier(for: pet, kind: .birthday)
        }
        XCTAssertEqual(birthday?.dateComponents.month, 6)
        XCTAssertEqual(birthday?.dateComponents.day, 1)
    }

    func testRemoveRemindersAfterPetDeletion() async {
        let pet = Pet(name: "小橘", birthday: date(2020, 5, 1), adoptionDay: date(2021, 6, 2))
        let (service, poster, _, _) = makeService(pets: [pet])

        await service.removeReminders(for: pet)

        XCTAssertEqual(Set(poster.removedIdentifiers), Set(NotifyService.reminderIdentifiers(for: pet)))
        XCTAssertTrue(poster.scheduled.isEmpty)
    }

    // MARK: - 开关撤销

    func testCancelAllNotificationsRemovesEverything() async {
        let (service, poster, _, _) = makeService()
        await service.cancelAllNotifications()
        XCTAssertEqual(poster.removeAllCount, 1)
    }

    // MARK: - 授权转发

    func testRequestAuthorizationForwardsToPoster() async {
        let (service, poster, _, _) = makeService()
        poster.authorizationResult = false

        let granted = await service.requestAuthorization()

        XCTAssertFalse(granted)
        XCTAssertEqual(poster.authorizationRequestCount, 1)
    }

    // MARK: - 新照片提醒调度

    /// 构造带新照片提醒 provider 的服务
    private func makeServiceWithNewPhoto(
        lastAddedDate: Date?,
        newPhotoCount: Int
    ) -> (NotifyService, MockNotificationPoster) {
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository()
        let poster = MockNotificationPoster()
        let service = NotifyService(
            photoRepo: photoRepo, petRepo: petRepo, poster: poster,
            lastAddedPhotoDateProvider: { lastAddedDate },
            newPhotoCountProvider: { newPhotoCount }
        )
        return (service, poster)
    }

    func testNewPhotoReminderScheduledWhenNewPhotosExist() async {
        let now = date(2026, 8, 13)
        let lastAdded = date(2026, 8, 10)  // 3 天前
        let (service, poster) = makeServiceWithNewPhoto(lastAddedDate: lastAdded, newPhotoCount: 5)

        await service.rescheduleAllReminders(now: now, calendar: calendar)

        let npr = poster.scheduled.first {
            $0.identifier == NotifyService.newPhotoReminderIdentifier
        }
        XCTAssertNotNil(npr, "有新照片时应调度提醒")
        XCTAssertEqual(npr?.repeats, false)
    }

    func testNewPhotoReminderScheduledWhenStale() async {
        let now = date(2026, 8, 13)
        let lastAdded = date(2026, 7, 1)  // 43 天前
        let (service, poster) = makeServiceWithNewPhoto(lastAddedDate: lastAdded, newPhotoCount: 0)

        await service.rescheduleAllReminders(now: now, calendar: calendar)

        let npr = poster.scheduled.first {
            $0.identifier == NotifyService.newPhotoReminderIdentifier
        }
        XCTAssertNotNil(npr, "久未添加时应调度提醒")
    }

    func testNewPhotoReminderNotScheduledWhenNoConditions() async {
        let now = date(2026, 8, 13)
        let lastAdded = date(2026, 8, 10)  // 3 天前
        let (service, poster) = makeServiceWithNewPhoto(lastAddedDate: lastAdded, newPhotoCount: 0)

        await service.rescheduleAllReminders(now: now, calendar: calendar)

        let npr = poster.scheduled.first {
            $0.identifier == NotifyService.newPhotoReminderIdentifier
        }
        XCTAssertNil(npr, "无新照片且未过期时不应调度")
    }

    func testNewPhotoReminderRemovesOldBeforeSchedule() async {
        let now = date(2026, 8, 13)
        let (service, poster) = makeServiceWithNewPhoto(lastAddedDate: nil, newPhotoCount: 3)

        await service.rescheduleAllReminders(now: now, calendar: calendar)

        // 幂等性验证：先撤销旧的通知（removeNotifications 调用过 newPhotoReminderIdentifier）
        XCTAssertTrue(poster.removedIdentifiers.contains(NotifyService.newPhotoReminderIdentifier),
                      "重调度时应先撤销旧的新照片提醒")
    }

    // MARK: - 备份提醒调度

    /// 构造带上次备份时间 provider 的服务
    private func makeServiceWithBackup(
        lastBackupDate: Date?
    ) -> (NotifyService, MockNotificationPoster) {
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository()
        let poster = MockNotificationPoster()
        let service = NotifyService(
            photoRepo: photoRepo, petRepo: petRepo, poster: poster,
            lastBackupDateProvider: { lastBackupDate }
        )
        return (service, poster)
    }

    func testBackupReminderScheduledWhenNeverBackedUp() async {
        let now = date(2026, 8, 13)
        let (service, poster) = makeServiceWithBackup(lastBackupDate: nil)

        await service.rescheduleAllReminders(now: now, calendar: calendar)

        let backup = poster.scheduled.first {
            $0.identifier == NotifyService.backupReminderIdentifier
        }
        XCTAssertNotNil(backup, "从未备份时应调度备份提醒")
        // 次日 09:00 单次通知（组件断言）
        XCTAssertEqual(backup?.dateComponents.year, 2026)
        XCTAssertEqual(backup?.dateComponents.month, 8)
        XCTAssertEqual(backup?.dateComponents.day, 14)
        XCTAssertEqual(backup?.dateComponents.hour, NotifyService.reminderHour)
        XCTAssertEqual(backup?.dateComponents.minute, NotifyService.reminderMinute)
        XCTAssertEqual(backup?.repeats, false)
    }

    func testBackupReminderScheduledWhenStale() async {
        let now = date(2026, 8, 13)
        let lastBackup = date(2026, 6, 14)  // 60 天前（≥ reminderStaleDays 阈值）
        let (service, poster) = makeServiceWithBackup(lastBackupDate: lastBackup)

        await service.rescheduleAllReminders(now: now, calendar: calendar)

        let backup = poster.scheduled.first {
            $0.identifier == NotifyService.backupReminderIdentifier
        }
        XCTAssertNotNil(backup, "距上次备份 ≥ 60 天时应调度提醒")
    }

    func testBackupReminderSkippedButCleanedWhenRecentlyBackedUp() async {
        let now = date(2026, 8, 13)
        let lastBackup = date(2026, 8, 1)  // 12 天前（刚备份过）
        let (service, poster) = makeServiceWithBackup(lastBackupDate: lastBackup)

        await service.rescheduleAllReminders(now: now, calendar: calendar)

        let backup = poster.scheduled.first {
            $0.identifier == NotifyService.backupReminderIdentifier
        }
        XCTAssertNil(backup, "刚备份过（< 60 天）不应调度")
        // 幂等清理：无论是否调度都先撤销旧的备份提醒通知（不残留过期提醒）
        XCTAssertTrue(poster.removedIdentifiers.contains(NotifyService.backupReminderIdentifier),
                      "不调度时也应先撤销旧的备份提醒")
    }

    func testBackupReminderNotScheduledAt59Days() async {
        let now = date(2026, 8, 13)
        let lastBackup = date(2026, 6, 15)  // 59 天前（阈值边界内侧）
        let (service, poster) = makeServiceWithBackup(lastBackupDate: lastBackup)

        await service.rescheduleAllReminders(now: now, calendar: calendar)

        let backup = poster.scheduled.first {
            $0.identifier == NotifyService.backupReminderIdentifier
        }
        XCTAssertNil(backup, "59 天（< 60 天阈值）不应调度")
    }
}
