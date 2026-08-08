import XCTest
@testable import MiLens

/// NotifyService 编排测试——纪念日 + 时光机发布、每日去重、授权拒绝、撤销。
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
        authorization: Bool = true,
        random: Int = 0
    ) -> (NotifyService, MockNotificationPoster, InMemoryPhotoRepository, InMemoryPetRepository, UserDefaults) {
        let photoRepo = InMemoryPhotoRepository(photos: photos)
        let petRepo = InMemoryPetRepository(pets: pets)
        let poster = MockNotificationPoster()
        poster.authorizationResult = authorization
        // 每个用例独立 suite，天然隔离（避免 UserDefaults 跨测试残留）
        let defaults = UserDefaults(suiteName: "test-notify-\(UUID().uuidString)")!
        let service = NotifyService(
            photoRepo: photoRepo, petRepo: petRepo, poster: poster,
            defaults: defaults, randomSource: { random }
        )
        return (service, poster, photoRepo, petRepo, defaults)
    }

    private func photo(_ id: String, takenAt: Date?, note: String = "纪念日", pet: Pet? = nil) -> Photo {
        Photo(uri: id, pet: pet, takenAt: takenAt, note: note)
    }

    // MARK: - 纪念日 + 时光机

    func testDailyCheckPostsAnniversaryAndTimeMachine() async {
        let pet = Pet(name: "小橘")
        let today = date(2026, 8, 8)
        let photos = [
            photo("hist-2025", takenAt: date(2025, 8, 8), note: "第一次见面", pet: pet),  // 去年今日
            photo("cur-2026", takenAt: today, note: "今天的照片"),                          // 今年今日
            photo("other-day", takenAt: date(2025, 8, 9), note: "不是今天"),               // 非同日
        ]
        let (service, poster, _, _, _) = makeService(photos: photos, pets: [pet])

        await service.runDailyCheck(now: today, calendar: calendar)

        // 纪念日：2 条（去年今日 + 今年今日；8月9日不匹配）
        let anniversary = poster.posted.filter { !$0.identifier.hasPrefix("tm-") }
        XCTAssertEqual(anniversary.count, 2)
        XCTAssertTrue(anniversary.contains { $0.title == "纪念日回忆" && $0.body == "1年前的今天：第一次见面" })
        XCTAssertTrue(anniversary.contains { $0.title == "纪念日回忆" && $0.body == "今天的回忆：今天的照片" })

        // 时光机：1 条（排除当年后随机选一张）
        let timeMachine = poster.posted.filter { $0.identifier.hasPrefix("tm-") }
        XCTAssertEqual(timeMachine.count, 1)
        XCTAssertEqual(timeMachine.first?.title, "1年前的今天")
        XCTAssertTrue(timeMachine.first!.identifier.hasPrefix("tm-"))
    }

    func testTimeMachineOnlyUsesHistoricalPhotos() async {
        // 只有今年今日的照片：纪念日 1 条，时光机 0 条
        let photos = [
            photo("cur-2026", takenAt: date(2026, 8, 8), note: "今年今天"),
        ]
        let (service, poster, _, _, _) = makeService(photos: photos)

        await service.runDailyCheck(now: date(2026, 8, 8), calendar: calendar)

        let anniversary = poster.posted.filter { !$0.identifier.hasPrefix("tm-") }
        let timeMachine = poster.posted.filter { $0.identifier.hasPrefix("tm-") }
        XCTAssertEqual(anniversary.count, 1)
        XCTAssertTrue(timeMachine.isEmpty)
    }

    func testTimeMachineUsesRandomIndexForSelection() async {
        let photos = [
            photo("a", takenAt: date(2024, 8, 8), note: "A"),
            photo("b", takenAt: date(2025, 8, 8), note: "B"),
        ]
        // 仓储按拍摄时间倒序返回 [b(2025), a(2024)]，random = 1 → 选中 a(2024) → "2年前的今天"
        let (service, poster, _, _, _) = makeService(photos: photos, random: 1)

        await service.runDailyCheck(now: date(2026, 8, 8), calendar: calendar)

        let timeMachine = poster.posted.filter { $0.identifier.hasPrefix("tm-") }
        XCTAssertEqual(timeMachine.count, 1)
        XCTAssertEqual(timeMachine.first?.title, "2年前的今天")
    }

    // MARK: - 每日去重

    func testDailyCheckRunsOnlyOncePerDay() async {
        let photos = [photo("a", takenAt: date(2025, 8, 8), note: "A")]
        let (service, poster, _, _, _) = makeService(photos: photos)

        let today = date(2026, 8, 8)
        await service.runDailyCheck(now: today, calendar: calendar)
        await service.runDailyCheck(now: today, calendar: calendar)  // 同日重复

        XCTAssertEqual(poster.posted.count, 2, "纪念日 + 时光机各 1 条，同日不重复发布")
        XCTAssertEqual(poster.authorizationRequestCount, 1)
    }

    func testDailyCheckRunsAgainNextDay() async {
        let photos = [photo("a", takenAt: date(2025, 8, 8), note: "A")]
        let (service, poster, _, _, _) = makeService(photos: photos)

        let today = date(2026, 8, 8)
        await service.runDailyCheck(now: today, calendar: calendar)
        let firstCount = poster.posted.count
        // 次日无同日照片 → 不发布但仍标记
        await service.runDailyCheck(now: date(2026, 8, 9), calendar: calendar)

        XCTAssertEqual(poster.posted.count, firstCount)
        XCTAssertEqual(poster.authorizationRequestCount, 2)
    }

    // MARK: - 授权拒绝

    func testDeniedAuthorizationSkipsPostingButMarksChecked() async {
        let photos = [photo("a", takenAt: date(2025, 8, 8), note: "A")]
        let (service, poster, _, _, _) = makeService(photos: photos, authorization: false)

        let today = date(2026, 8, 8)
        await service.runDailyCheck(now: today, calendar: calendar)
        XCTAssertTrue(poster.posted.isEmpty, "授权拒绝时不发布")

        // 已标记当日，同日再次激活不再请求授权
        await service.runDailyCheck(now: today, calendar: calendar)
        XCTAssertEqual(poster.authorizationRequestCount, 1)
    }

    // MARK: - 无照片

    func testNoPhotosStillMarksChecked() async {
        let (service, poster, _, _, _) = makeService()

        await service.runDailyCheck(now: date(2026, 8, 8), calendar: calendar)
        XCTAssertTrue(poster.posted.isEmpty)
        // 同日重复调用不再请求授权（已标记）
        await service.runDailyCheck(now: date(2026, 8, 8), calendar: calendar)
        XCTAssertEqual(poster.authorizationRequestCount, 1)
    }

    // MARK: - 撤销

    func testCancelAllNotificationsRemovesEverything() async {
        let (service, poster, _, _, _) = makeService()
        await service.cancelAllNotifications()
        XCTAssertEqual(poster.removeAllCount, 1)
    }
}

// MARK: - 纯内存 mock

/// 内存照片仓储：支持纪念日过滤语义（eventNotify + note 非空 + MM-DD + 排除年份）。
@MainActor
private final class InMemoryPhotoRepository: PhotoRepositoryProtocol {
    private var photos: [Photo]

    init(photos: [Photo] = []) {
        self.photos = photos
    }

    func getPhoto(id: UUID) throws -> Photo? { photos.first { $0.id == id } }
    func getPhotoByURI(_ uri: String) throws -> Photo? { photos.first { $0.uri == uri } }
    func getAllPhotoURIs() throws -> Set<String> { Set(photos.map(\.uri)) }
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] {
        Array(photos.sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }.dropFirst(offset).prefix(limit))
    }
    func getPhotosByPet(_ pet: Pet) throws -> [Photo] {
        photos.filter { $0.pet?.id == pet.id }
    }
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo] {
        photos
            .filter { $0.eventNotify && !$0.note.isEmpty }
            .filter { NotifyCheckLogic.matchesMonthDay($0.takenAt, month: month, day: day, calendar: utcCalendar) }
            .filter { photo in
                guard let excludeYear else { return true }
                return !NotifyCheckLogic.isInYear(photo.takenAt, year: excludeYear, calendar: utcCalendar)
            }
            .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
    }
    func insertPhoto(_ photo: Photo) throws { photos.append(photo) }
    func deletePhoto(_ photo: Photo) throws { photos.removeAll { $0.id == photo.id } }
    func updatePhoto(_ photo: Photo) throws {}
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws { photo.pet = pet }
    func setFavorite(_ photo: Photo, favorite: Bool) throws { photo.isFavorite = favorite }
    func updateNote(_ photo: Photo, note: String) throws { photo.note = note }
    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo] { [] }
    func getDuplicateCandidates() throws -> [Photo] { [] }
    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws {}
    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws {}
}

/// 内存宠物仓储。
@MainActor
private final class InMemoryPetRepository: PetRepositoryProtocol {
    private var pets: [Pet]

    init(pets: [Pet] = []) {
        self.pets = pets
    }

    func getAllPets() throws -> [Pet] { pets }
    func getPet(id: UUID) throws -> Pet? { pets.first { $0.id == id } }
    func insertPet(_ pet: Pet) throws { pets.append(pet) }
    func updatePet(_ pet: Pet) throws {}
    func deletePet(_ pet: Pet) throws { pets.removeAll { $0.id == pet.id } }
    func refreshPhotoCount(for pet: Pet) throws {}
}
