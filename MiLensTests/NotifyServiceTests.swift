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

    // MARK: - 时光机（每日 09:00）

    func testRescheduleSchedulesTimeMachineWhenHistoricalPhotosExist() async {
        let photos = [photo("a", takenAt: date(2025, 8, 8), note: "A")]
        let (service, poster, _, _) = makeService(photos: photos)

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        let tm = poster.scheduled.first {
            $0.identifier == NotifyService.timeMachineIdentifier
        }
        XCTAssertNotNil(tm)
        XCTAssertEqual(tm?.dateComponents.hour, NotifyService.reminderHour)
        XCTAssertEqual(tm?.dateComponents.minute, NotifyService.reminderMinute)
        XCTAssertNil(tm?.dateComponents.month, "仅时分 = 每日重复")
        XCTAssertEqual(tm?.repeats, true)
        XCTAssertEqual(tm?.title, "1年前的今天")
    }

    func testRescheduleSkipsTimeMachineWithoutHistoricalPhotos() async {
        // 只有今年今日的照片（时光机排除当年）→ 不调度每日通知
        let photos = [photo("cur", takenAt: date(2026, 8, 8), note: "今年")]
        let (service, poster, _, _) = makeService(photos: photos)

        await service.rescheduleAllReminders(now: date(2026, 8, 8), calendar: calendar)

        XCTAssertFalse(poster.scheduled.contains {
            $0.identifier == NotifyService.timeMachineIdentifier
        })
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
    func getPhotoByOriginalURI(_ originalURI: String) throws -> Photo? { photos.first { $0.originalURI == originalURI } }
    func getAllOriginalURIs() throws -> Set<String> { Set(photos.map(\.originalURI)) }
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
    func updateFeatureData(_ pet: Pet, data: Data?) throws {}
}
