import XCTest
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

        // 领养日：anniversary-<petID>-adoption，6/2 09:00 每年重复
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

        XCTAssertTrue(poster.scheduled.isEmpty)
    }

    func testBirthdayBodyReusesAnniversaryWording() async {
        let pet = Pet(name: "小橘", birthday: date(2020, 5, 1))
        let (service, poster, _, _) = makeService(pets: [pet])

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        let birthday = poster.scheduled.first {
            $0.identifier == NotifyService.anniversaryIdentifier(for: pet, kind: .birthday)
        }
        XCTAssertEqual(birthday?.title, "纪念日回忆")
        XCTAssertEqual(birthday?.body, "今天的回忆：小橘的生日")
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
        // 同一 identifier 重复调度由系统覆盖（mock 追加记录），去重后仍只有一份数据
        XCTAssertEqual(Set(poster.scheduled.map(\.identifier)).count, 1)
    }

    // MARK: - 宠物编辑/删除局部更新

    func testUpdateRemindersReschedulesPetAfterEdit() async {
        let pet = Pet(name: "小橘", birthday: date(2020, 5, 1))
        let (service, poster, _, _) = makeService(pets: [pet])

        // 编辑：生日改为 6/1
        pet.birthday = date(2020, 6, 1)
        await service.updateReminders(for: pet, calendar: calendar)

        // 先撤销旧的两个 identifier（birthday + adoption）
        XCTAssertEqual(Set(poster.removedIdentifiers), Set(NotifyService.anniversaryIdentifiers(for: pet)))
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

        XCTAssertEqual(Set(poster.removedIdentifiers), Set(NotifyService.anniversaryIdentifiers(for: pet)))
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
}
