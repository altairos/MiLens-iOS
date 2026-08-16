//  TimelineViewModelTests —— 成长时间线 ViewModel 状态机测试。
//  覆盖：空库加载、免费 365 天截断 + hasLockedHistory、Pro 全量、
//  新用户全历史预览（全显/剩余天数/临期提醒/过期回落锁定）、
//  按宠物筛选、添加记忆（空标题/成功写 PetEvent(sourceType="user")/保存失败）、
//  宠物列表读取失败兜底。
//  日期全部用 UTC 构造对齐 PetDateCalendar（TimelineLogic/TimelineAccessLogic 均为 UTC 口径）。

import XCTest
@testable import MiLens

@MainActor
final class TimelineViewModelTests: XCTestCase {

    private var calendar: Calendar { utcCalendar }

    /// UTC 某日 12:00（避开日界，保证 UTC 口径下的月日拆分稳定）。
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.timeZone = TimeZone(identifier: "UTC")
        return calendar.date(from: comps)!
    }

    private func makeVM(pets: [Pet] = [], photos: [Photo] = []) -> TimelineViewModel {
        TimelineViewModel(
            petRepo: InMemoryPetRepository(pets: pets),
            photoRepo: InMemoryPhotoRepository(photos: photos)
        )
    }

    /// now 固定 UTC 2026-08-17 12:00：老宠物（2020-01-15 生日）历年生日条目 6 条，
    /// 免费截断（cutoff 2025-08-17）后仅剩 2026-01-15 一条。
    private var now: Date { date(2026, 8, 17) }

    // MARK: - 空库

    func testLoadEmptyLibraryProducesNoMonths() {
        let vm = makeVM()

        vm.load(now: now)

        XCTAssertTrue(vm.months.isEmpty)
        XCTAssertEqual(vm.totalCount, 0)
        XCTAssertEqual(vm.filteredCount, 0)
        XCTAssertFalse(vm.hasLockedHistory)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - 免费/Pro 可见性

    func testFreeTierHidesEntriesOlderThanOneYear() {
        let pet = Pet(name: "小橘", birthday: date(2020, 1, 15))
        let vm = makeVM(pets: [pet])

        vm.load(now: now, isPro: false)

        // 历年生日 2021…2026 共 6 条；cutoff=now-365d=2025-08-17 → 仅 2026-01-15 可见
        XCTAssertEqual(vm.totalCount, 1)
        XCTAssertTrue(vm.hasLockedHistory)
        XCTAssertEqual(vm.months.count, 1)
        XCTAssertEqual(vm.months[0].year, 2026)
        XCTAssertEqual(vm.months[0].month, 1)
    }

    func testProTierShowsFullHistory() {
        let pet = Pet(name: "小橘", birthday: date(2020, 1, 15))
        let vm = makeVM(pets: [pet])

        vm.load(now: now, isPro: true)

        XCTAssertEqual(vm.totalCount, 6)
        XCTAssertFalse(vm.hasLockedHistory)
        XCTAssertEqual(vm.months.count, 6)
        XCTAssertEqual(vm.months.first?.year, 2021)
        XCTAssertEqual(vm.months.last?.year, 2026)
    }

    // MARK: - 新用户全历史预览

    func testFullHistoryPreviewShowsEverythingForFreeUser() {
        let pet = Pet(name: "小橘", birthday: date(2020, 1, 15))
        let vm = makeVM(pets: [pet])
        let firstAccess = date(2026, 8, 14) // 3 天前

        vm.load(now: now, isPro: false, firstAccessDate: firstAccess)

        XCTAssertTrue(vm.isInFullHistoryPreview)
        XCTAssertEqual(vm.previewDaysRemaining, 11)
        XCTAssertEqual(vm.totalCount, 6, "预览期内免费用户可见全部历史")
        XCTAssertFalse(vm.hasLockedHistory)
        XCTAssertFalse(vm.shouldShowPreviewReminder, "剩余 11 天 > 4，未到临期提醒")
    }

    func testPreviewReminderAppearsInLastFourDays() {
        let pet = Pet(name: "小橘", birthday: date(2020, 1, 15))
        let vm = makeVM(pets: [pet])
        let firstAccess = date(2026, 8, 6) // 11 天前

        vm.load(now: now, isPro: false, firstAccessDate: firstAccess)

        XCTAssertTrue(vm.isInFullHistoryPreview)
        XCTAssertEqual(vm.previewDaysRemaining, 3)
        XCTAssertTrue(vm.shouldShowPreviewReminder, "剩余 3 天 ≤ 4 且存在历史内容")
    }

    func testPreviewExpiryRestoresFreeTierLock() {
        let pet = Pet(name: "小橘", birthday: date(2020, 1, 15))
        let vm = makeVM(pets: [pet])
        let firstAccess = date(2026, 7, 28) // 20 天前，预览已过期

        vm.load(now: now, isPro: false, firstAccessDate: firstAccess)

        XCTAssertFalse(vm.isInFullHistoryPreview)
        XCTAssertEqual(vm.previewDaysRemaining, 0)
        XCTAssertTrue(vm.hasLockedHistory, "预览过期后回到免费 365 天截断")
        XCTAssertEqual(vm.totalCount, 1)
    }

    // MARK: - 按宠物筛选

    func testSelectPetFiltersMonths() {
        let petA = Pet(name: "小橘")
        let petB = Pet(name: "小白")
        let photos = [
            Photo(uri: "test://a1", pet: petA, takenAt: date(2026, 7, 10)),
            Photo(uri: "test://a2", pet: petA, takenAt: date(2026, 6, 20))
        ]
        let vm = makeVM(pets: [petA, petB], photos: photos)
        vm.load(now: now)
        XCTAssertEqual(vm.totalCount, 2)
        XCTAssertEqual(vm.filteredCount, 2)

        vm.selectPet(petB.id)
        XCTAssertTrue(vm.months.isEmpty)
        XCTAssertEqual(vm.filteredCount, 0, "小白无任何条目")

        vm.selectPet(nil)
        XCTAssertEqual(vm.filteredCount, 2, "nil = 全部宠物")
    }

    // MARK: - 添加记忆

    func testAddMemoryRejectsBlankTitle() {
        let pet = Pet(name: "小橘")
        let vm = makeVM(pets: [pet])

        XCTAssertFalse(vm.addMemory(to: pet, title: "   ", date: now, body: ""))
        XCTAssertEqual(vm.addMemoryError, String(localized: "timeline.addMemory.titleRequired"))
    }

    func testAddMemoryWritesUserEventAndRefreshes() {
        let pet = Pet(name: "小橘")
        let vm = makeVM(pets: [pet])
        vm.load(now: now)
        XCTAssertEqual(vm.totalCount, 0)

        let ok = vm.addMemory(to: pet, title: " 第一次旅行 ", date: date(2026, 8, 1), body: " 海边 ", now: now)

        XCTAssertTrue(ok)
        XCTAssertEqual(vm.addMemoryError, "")
        XCTAssertEqual(pet.events.count, 1)
        XCTAssertEqual(pet.events[0].sourceType, "user")
        XCTAssertEqual(pet.events[0].eventType, "custom")
        XCTAssertEqual(pet.events[0].title, "第一次旅行", "标题应去空格")
        XCTAssertEqual(pet.events[0].body, "海边")
        XCTAssertEqual(vm.totalCount, 1, "保存成功后时间线应刷新")
        XCTAssertEqual(vm.months.first?.year, 2026)
        XCTAssertEqual(vm.months.first?.month, 8)
    }

    func testAddMemoryReportsSaveFailure() {
        let repo = FlakyPetRepository()
        let pet = Pet(name: "小橘")
        try? repo.insertPet(pet)
        repo.failAddEvent = true
        let vm = TimelineViewModel(petRepo: repo, photoRepo: InMemoryPhotoRepository())

        XCTAssertFalse(vm.addMemory(to: pet, title: "第一次旅行", date: now, body: ""))
        XCTAssertEqual(vm.addMemoryError, String(localized: "timeline.addMemory.saveFailed"))
    }

    // MARK: - 仓储失败兜底

    func testLoadWithFailingPetRepositoryYieldsEmptyTimeline() throws {
        let repo = FlakyPetRepository()
        try repo.insertPet(Pet(name: "小橘"))
        repo.failGetAll = true
        let vm = TimelineViewModel(petRepo: repo, photoRepo: InMemoryPhotoRepository())

        vm.load(now: now)

        XCTAssertTrue(vm.months.isEmpty)
        XCTAssertEqual(vm.totalCount, 0)
        XCTAssertFalse(vm.isLoading, "读取失败也应结束 loading 态")
    }

    // MARK: - 查询

    func testPhotosForPetReturnsOwnedPhotosOnly() {
        let petA = Pet(name: "小橘")
        let petB = Pet(name: "小白")
        let photoA = Photo(uri: "test://a", pet: petA, takenAt: date(2026, 7, 1))
        let photoB = Photo(uri: "test://b", pet: petB, takenAt: date(2026, 7, 2))
        let vm = makeVM(pets: [petA, petB], photos: [photoA, photoB])

        let owned = vm.photos(for: petA)

        XCTAssertEqual(owned.map(\.uri), ["test://a"])
    }
}
