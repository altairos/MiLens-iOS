import XCTest
@testable import MiLens

/// MemoryRemindersViewModel 状态投影测试。
///
/// 用 InMemoryRepositories 验证 todayItems / upcomingItems / memoryItems 装配、
/// hasTodayContent / isEmpty 计算属性、加载错误回退。
/// 与 SettingsViewModelTests 同策略：纯内存 mock，不碰 SwiftData。
@MainActor
final class MemoryRemindersViewModelTests: XCTestCase {

    private var calendar: Calendar {
        utcCalendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.timeZone = TimeZone(identifier: "UTC")
        return calendar.date(from: comps)!
    }

    // MARK: - 今日命中

    func testTodayBirthdayHitLoads() {
        let pet = Pet(name: "小橘", birthday: date(2020, 8, 13))
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet])
        let now = date(2026, 8, 13)

        let vm = MemoryRemindersViewModel(
            photoRepository: photoRepo, petRepository: petRepo,
            now: { now }
        )
        vm.load()

        XCTAssertTrue(vm.hasTodayContent)
        XCTAssertEqual(vm.todayItems.count, 1)
        XCTAssertEqual(vm.todayItems.first?.kind, .birthday)
    }

    func testTodayMemoryHitLoads() {
        let pet = Pet(name: "小橘")
        let photo = Photo(uri: "test://1", pet: pet, takenAt: date(2024, 8, 13), note: "散步")
        let photoRepo = InMemoryPhotoRepository(photos: [photo])
        let petRepo = InMemoryPetRepository(pets: [pet])
        let now = date(2026, 8, 13)

        let vm = MemoryRemindersViewModel(
            photoRepository: photoRepo, petRepository: petRepo,
            now: { now }
        )
        vm.load()

        XCTAssertTrue(vm.hasTodayContent)
        XCTAssertTrue(vm.todayItems.contains { $0.kind == .memory })
    }

    func testNoTodayContentWhenNoHits() {
        let pet = Pet(name: "小橘", birthday: date(2020, 1, 1))
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet])
        let now = date(2026, 8, 13)

        let vm = MemoryRemindersViewModel(
            photoRepository: photoRepo, petRepository: petRepo,
            now: { now }
        )
        vm.load()

        XCTAssertFalse(vm.hasTodayContent)
        XCTAssertTrue(vm.todayItems.isEmpty)
    }

    // MARK: - 即将到来的日子

    func testUpcomingItemsSorted() {
        let pet1 = Pet(name: "A", birthday: date(2020, 9, 1))
        let pet2 = Pet(name: "B", birthday: date(2020, 8, 20))
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet1, pet2])
        let now = date(2026, 8, 13)

        let vm = MemoryRemindersViewModel(
            photoRepository: photoRepo, petRepository: petRepo,
            now: { now }
        )
        vm.load()

        XCTAssertEqual(vm.upcomingItems.count, 2)
        XCTAssertEqual(vm.upcomingItems[0].petName, "B")
        XCTAssertEqual(vm.upcomingItems[1].petName, "A")
    }

    // MARK: - 往日回忆

    func testMemoryItemsLoadedWithThumbnail() {
        let pet = Pet(name: "小橘")
        let photo = Photo(
            uri: "test://1", pet: pet,
            takenAt: date(2024, 8, 13),
            note: "散步",
            thumbnailPath: "thumb://1"
        )
        let photoRepo = InMemoryPhotoRepository(photos: [photo])
        let petRepo = InMemoryPetRepository(pets: [pet])
        let now = date(2026, 8, 13)

        let vm = MemoryRemindersViewModel(
            photoRepository: photoRepo, petRepository: petRepo,
            now: { now }
        )
        vm.load()

        XCTAssertFalse(vm.memoryItems.isEmpty)
        XCTAssertEqual(vm.memoryItems.first?.thumbnailPath, "thumb://1")
    }

    // MARK: - 空态

    func testIsEmptyWhenNoData() {
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository()
        let now = date(2026, 8, 13)

        let vm = MemoryRemindersViewModel(
            photoRepository: photoRepo, petRepository: petRepo,
            now: { now }
        )
        vm.load()

        XCTAssertTrue(vm.isEmpty)
    }

    func testIsNotEmptyWhenHasUpcoming() {
        let pet = Pet(name: "小橘", birthday: date(2020, 12, 25))
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet])
        let now = date(2026, 8, 13)

        let vm = MemoryRemindersViewModel(
            photoRepository: photoRepo, petRepository: petRepo,
            now: { now }
        )
        vm.load()

        XCTAssertFalse(vm.isEmpty)
        XCTAssertTrue(vm.todayItems.isEmpty)
        XCTAssertFalse(vm.upcomingItems.isEmpty)
    }

    // MARK: - 加载状态

    func testLoadSetsIsLoadingFalse() {
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository()

        let vm = MemoryRemindersViewModel(
            photoRepository: photoRepo, petRepository: petRepo
        )

        XCTAssertTrue(vm.isLoading)
        vm.load()
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.loadError)
    }
}
