//  HomeViewModelTests —— 首页 ViewModel 快照与决策投影测试。
//  覆盖：问候分段（本地时）、load 快照装配（含「N 年前的今天」回忆）、
//  加载失败兜底、hero 选片（今日最新优先/质量回退池/无候选）、
//  今日提醒命中（生日投影）、新照片提醒分支（无依赖/both/newPhotos/staleInput）、
//  备份横幅阈值（20 张门槛/30 天过期/会话级关闭）、
//  即将到来的纪念日（跨年推进/取最近含今天/memorial 事件/缩略图回填）。
//  日历口径与源码对齐：hero/回忆/今日提醒为 UTC（utcDate 构造），
//  问候与 upcomingDay 用 Calendar.current（localDate/localHour 构造，月日稳定）。

import XCTest
@testable import MiLens

// MARK: - 失败注入照片仓储（load 兜底用；InMemoryPhotoRepository 为 final 不可继承）

struct PhotoRepositoryFailure: Error {}

@MainActor
final class FlakyPhotoRepository: PhotoRepositoryProtocol {
    private let base: InMemoryPhotoRepository
    /// 失败注入：getPhotosPage 抛错（首页首步读取，触发 load 兜底分支）。
    var failGetPage = false

    init(photos: [Photo] = []) {
        base = InMemoryPhotoRepository(photos: photos)
    }

    func getPhoto(id: UUID) throws -> Photo? { try base.getPhoto(id: id) }
    func getPhotoByURI(_ uri: String) throws -> Photo? { try base.getPhotoByURI(uri) }
    func getPhotoByOriginalURI(_ originalURI: String) throws -> Photo? {
        try base.getPhotoByOriginalURI(originalURI)
    }
    func getAllOriginalURIs() throws -> Set<String> { try base.getAllOriginalURIs() }
    func getAllPhotoURIs() throws -> Set<String> { try base.getAllPhotoURIs() }
    func countAllPhotos() throws -> Int { try base.countAllPhotos() }
    func getLatestPhotoDate() throws -> Date? { try base.getLatestPhotoDate() }
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] {
        guard !failGetPage else { throw PhotoRepositoryFailure() }
        return try base.getPhotosPage(offset: offset, limit: limit)
    }
    func getPhotosByPet(_ pet: Pet) throws -> [Photo] { try base.getPhotosByPet(pet) }
    func getUnassignedPhotos(limit: Int) throws -> [Photo] { try base.getUnassignedPhotos(limit: limit) }
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo] {
        try base.getAnniversaryPhotos(month: month, day: day, excludeYear: excludeYear)
    }
    func insertPhoto(_ photo: Photo) throws { try base.insertPhoto(photo) }
    func insertPhotos(_ photos: [Photo]) throws { try base.insertPhotos(photos) }
    func deletePhoto(_ photo: Photo) throws { try base.deletePhoto(photo) }
    func updatePhoto(_ photo: Photo) throws { try base.updatePhoto(photo) }
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws { try base.assignPhoto(photo, to: pet) }
    func batchAssignPhotos(_ photos: [Photo], to targetPet: Pet?) throws -> [Pet] {
        try base.batchAssignPhotos(photos, to: targetPet)
    }
    func setFavorite(_ photo: Photo, favorite: Bool) throws { try base.setFavorite(photo, favorite: favorite) }
    func updateNote(_ photo: Photo, note: String) throws { try base.updateNote(photo, note: note) }
    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo] {
        try base.getPendingQualityScorePhotos(limit: limit)
    }
    func getDuplicateCandidates() throws -> [Photo] { try base.getDuplicateCandidates() }
    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws {
        try base.updateQualityData(photo, sharpness: sharpness, qualityScore: qualityScore, phash: phash)
    }
    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws {
        try base.replaceDuplicateMarks(groups)
    }
}

@MainActor
final class HomeViewModelTests: XCTestCase {

    // MARK: - 日期 helpers（两种口径分开构造）

    /// UTC 某日 12:00 —— hero / 回忆 / 今日提醒均为 UTC 口径。
    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        comps.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: comps)!
    }

    /// 本地某日 12:00 —— upcomingDay 用 Calendar.current，按本地日历构造月日稳定。
    private func localDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        return Calendar.current.date(from: comps)!
    }

    /// 本地今日某整点 —— 问候分段与 Calendar.current 同口径。
    private func localHour(_ hour: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        return Calendar.current.date(from: comps)!
    }

    /// 注入的「现在」：UTC 口径判定用 UTC 时刻，upcomingDay 用本地时刻（同一天）。
    private var now: Date { utcDate(2026, 8, 17) }
    private var localNow: Date { localDate(2026, 8, 17) }

    // MARK: - VM 工厂

    private func makeVM(
        pets: [Pet] = [],
        photos: [Photo] = [],
        photoLibrary: (any PhotoLibraryAccess)? = nil,
        scanCursorStore: (any ScanCursorStore)? = nil,
        now: @escaping () -> Date = { Date() }
    ) -> HomeViewModel {
        HomeViewModel(
            photoRepository: InMemoryPhotoRepository(photos: photos),
            petRepository: InMemoryPetRepository(pets: pets),
            photoLibrary: photoLibrary,
            scanCursorStore: scanCursorStore,
            now: now
        )
    }

    // MARK: - UserDefaults 备份/恢复（shouldShowBackupBanner 硬编码 standard 域）

    override func setUp() {
        super.setUp()
        // setUp 继承 nonisolated：经 assumeIsolated 进入主隔离读 @MainActor static key；
        // 备份值先拆成 Sendable 的 Date? 再交给 @Sendable teardown 闭包捕获。
        MainActor.assumeIsolated {
            let key = BackupViewModel.lastBackupDateKey
            let saved = UserDefaults.standard.object(forKey: key) as? Date
            UserDefaults.standard.removeObject(forKey: key)
            addTeardownBlock {
                if let saved {
                    UserDefaults.standard.set(saved, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
    }

    private func setLastBackup(_ date: Date?) {
        if let date {
            UserDefaults.standard.set(date, forKey: BackupViewModel.lastBackupDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: BackupViewModel.lastBackupDateKey)
        }
    }

    // MARK: - 问候

    func testGreetingFollowsLocalHourSegments() {
        XCTAssertEqual(makeVM(now: { self.localHour(8) }).greeting, "早上好")
        XCTAssertEqual(makeVM(now: { self.localHour(14) }).greeting, "下午好")
        XCTAssertEqual(makeVM(now: { self.localHour(20) }).greeting, "晚上好")
        XCTAssertEqual(makeVM(now: { self.localHour(3) }).greeting, "晚上好", "凌晨归属晚间段")
    }

    // MARK: - load 快照装配

    func testLoadPopulatesSnapshotAndMemoryItems() {
        let pet = Pet(name: "小橘")
        // 2024-08-17：两年前的今天 → 回忆区命中「N 年前的今天」
        let photo = Photo(uri: "test://1", pet: pet, takenAt: utcDate(2024, 8, 17), note: "散步")
        let vm = makeVM(pets: [pet], photos: [photo], now: { self.now })

        vm.load()

        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.loadError)
        XCTAssertEqual(vm.photos.count, 1)
        XCTAssertEqual(vm.pets.count, 1)
        XCTAssertEqual(vm.photoTotalCount, 1)
        XCTAssertEqual(vm.memoryItems.count, 1)
        XCTAssertEqual(vm.memoryItems[0].entry.photoID, photo.id)
        XCTAssertEqual(vm.memoryItems[0].photo.id, photo.id)
        XCTAssertTrue(vm.hasTodayContent, "两年前的今天照片应命中今日提醒")
    }

    func testLoadFailureClearsSnapshotAndReportsError() {
        let repo = FlakyPhotoRepository()
        repo.failGetPage = true
        let vm = HomeViewModel(
            photoRepository: repo,
            petRepository: InMemoryPetRepository(pets: [Pet(name: "小橘")]),
            now: { self.now }
        )

        vm.load()

        XCTAssertTrue(vm.photos.isEmpty)
        XCTAssertTrue(vm.pets.isEmpty)
        XCTAssertTrue(vm.memoryItems.isEmpty)
        XCTAssertEqual(vm.photoTotalCount, 0)
        XCTAssertEqual(vm.loadError, String(localized: "home.loadError"))
        XCTAssertFalse(vm.isLoading, "失败也应结束 loading 态")
    }

    // MARK: - hero 选片

    func testHeroPhotoPrefersLatestOfToday() {
        let pet = Pet(name: "小橘")
        let photos = [
            Photo(uri: "test://old", pet: pet, takenAt: utcDate(2026, 8, 1), note: "", qualityScore: 0.9),
            Photo(uri: "test://earlier", pet: pet, takenAt: now.addingTimeInterval(-60), qualityScore: 0.1),
            Photo(uri: "test://latest", pet: pet, takenAt: now, qualityScore: 0.1),
        ]
        let vm = makeVM(pets: [pet], photos: photos, now: { self.now })
        vm.load()

        XCTAssertEqual(vm.heroPhoto?.uri, "test://latest", "今日有多张时取最新一张（与质量分无关）")
        XCTAssertTrue(vm.heroIsToday)
        XCTAssertEqual(vm.heroCaption, "今天 · 小橘")
    }

    func testHeroPhotoFallsBackToQualityPoolWhenNoToday() {
        let pet = Pet(name: "小橘")
        // 单张候选：top 池必含该照片，随机种子模 1 恒定
        let photo = Photo(uri: "test://1", pet: pet, takenAt: utcDate(2026, 8, 1), qualityScore: 0.5)
        let vm = makeVM(pets: [pet], photos: [photo], now: { self.now })
        vm.load()

        XCTAssertEqual(vm.heroPhoto?.id, photo.id)
        XCTAssertFalse(vm.heroIsToday)
        XCTAssertEqual(vm.heroCaption, "最近 · 小橘")
    }

    func testHeroPhotoNilWhenNoTimestampedPhotos() {
        let vm = makeVM(photos: [Photo(uri: "test://a"), Photo(uri: "test://b")], now: { self.now })
        vm.load()

        XCTAssertNil(vm.heroPhoto, "全部无拍摄时间时无 hero 候选")
        XCTAssertFalse(vm.heroIsToday)
        XCTAssertEqual(vm.heroCaption, "最近")
    }

    // MARK: - 今日提醒（生日投影）

    func testHasTodayContentTrueOnBirthdayMatch() {
        let pet = Pet(name: "小橘", birthday: utcDate(2020, 8, 17))
        let vm = makeVM(pets: [pet], now: { self.now })
        vm.load()

        XCTAssertTrue(vm.hasTodayContent)
    }

    func testHasTodayContentFalseOnOrdinaryDay() {
        let pet = Pet(name: "小橘", birthday: utcDate(2020, 12, 25))
        let vm = makeVM(pets: [pet], now: { self.now })
        vm.load()

        XCTAssertFalse(vm.hasTodayContent)
    }

    // MARK: - 新照片提醒

    func testRefreshReminderWithoutPlatformDependenciesIsNone() async {
        let vm = makeVM(now: { self.now })

        await vm.refreshNewPhotoReminder()

        XCTAssertEqual(vm.newPhotoReminderKind, .none)
        XCTAssertFalse(vm.hasNewPhotoReminder)
    }

    func testRefreshReminderResolvesBothForNewPhotosAndEmptyLibrary() async {
        let photoLibrary = MockPhotoLibraryAccess()
        photoLibrary.newPhotoCountOverride = 3
        let vm = makeVM(
            photoLibrary: photoLibrary,
            scanCursorStore: MockScanCursorStore(lastSuccessfulScan: utcDate(2026, 8, 16)),
            now: { self.now }
        )

        await vm.refreshNewPhotoReminder()

        // 有新照片（3 > 0）+ 空库从未导入 → both
        XCTAssertEqual(vm.newPhotoReminderKind, .both)
    }

    func testRefreshReminderResolvesNewPhotosOnlyWhenRecentlyAdded() async {
        let photo = Photo(uri: "test://1", takenAt: utcDate(2026, 8, 1))
        photo.createdAt = now // 最近添加 → 不触发久未添加
        let photoLibrary = MockPhotoLibraryAccess()
        photoLibrary.newPhotoCountOverride = 5
        let vm = HomeViewModel(
            photoRepository: InMemoryPhotoRepository(photos: [photo]),
            petRepository: InMemoryPetRepository(),
            photoLibrary: photoLibrary,
            scanCursorStore: MockScanCursorStore(lastSuccessfulScan: utcDate(2026, 8, 16)),
            now: { self.now }
        )

        await vm.refreshNewPhotoReminder()

        XCTAssertEqual(vm.newPhotoReminderKind, .newPhotos)
    }

    func testRefreshReminderResolvesStaleInputWithoutNewPhotos() async {
        let photoLibrary = MockPhotoLibraryAccess()
        photoLibrary.newPhotoCountOverride = 0
        let vm = makeVM(
            photoLibrary: photoLibrary,
            scanCursorStore: MockScanCursorStore(lastSuccessfulScan: utcDate(2026, 8, 16)),
            now: { self.now }
        )

        await vm.refreshNewPhotoReminder()

        // 无新照片 + 空库从未导入 → staleInput
        XCTAssertEqual(vm.newPhotoReminderKind, .staleInput)
    }

    // MARK: - 备份提醒横幅

    func testBackupBannerHiddenBelowPhotoThreshold() {
        let vm = makeVM(now: { self.now })
        vm.photoTotalCount = 19

        XCTAssertFalse(vm.shouldShowBackupBanner, "照片不足 20 张不打扰")
    }

    func testBackupBannerShowsAtThresholdAndDismissHidesForSession() {
        let vm = makeVM(now: { self.now })
        vm.photoTotalCount = 20

        XCTAssertTrue(vm.shouldShowBackupBanner, "达标 + 从未备份应展示")

        vm.dismissBackupBanner()
        XCTAssertFalse(vm.shouldShowBackupBanner, "用户关闭后本次会话不再展示")
    }

    func testBackupBannerHiddenAfterRecentBackup() {
        let vm = makeVM(now: { self.now })
        vm.photoTotalCount = 25
        setLastBackup(now.addingTimeInterval(-86_400)) // 1 天前

        XCTAssertFalse(vm.shouldShowBackupBanner)
    }

    func testBackupBannerReturnsAfterStaleBackup() {
        let vm = makeVM(now: { self.now })
        vm.photoTotalCount = 25
        setLastBackup(now.addingTimeInterval(-31 * 86_400)) // 31 天前

        XCTAssertTrue(vm.shouldShowBackupBanner, "距上次备份 ≥ 30 天应再次提醒")
    }

    // MARK: - 即将到来的纪念日

    func testUpcomingDayRollsToNextYearWhenPassed() throws {
        let pet = Pet(name: "小橘", birthday: localDate(2020, 1, 15))
        let vm = makeVM(pets: [pet], now: { self.localNow })
        vm.load()

        let upcoming = try XCTUnwrap(vm.upcomingDay)
        XCTAssertEqual(upcoming.kind, .birthday)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: upcoming.nextDate)
        XCTAssertEqual(comps.year, 2027)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 15, "今年生日已过，应推进到明年")
        let expectedDaysUntil = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: localNow),
            to: Calendar.current.startOfDay(for: upcoming.nextDate)).day
        XCTAssertEqual(upcoming.daysUntil, expectedDaysUntil)
        let expectedTogether = Calendar.current.dateComponents(
            [.day], from: localDate(2020, 1, 15), to: localNow).day
        XCTAssertEqual(upcoming.daysTogether, expectedTogether)
    }

    func testUpcomingDayPrefersTodayOverLaterCandidates() throws {
        let petA = Pet(name: "小橘", birthday: localDate(2020, 8, 17)) // 今天
        let petB = Pet(name: "小白", adoptionDay: localDate(2020, 8, 20)) // 3 天后
        let vm = makeVM(pets: [petA, petB], now: { self.localNow })
        vm.load()

        let upcoming = try XCTUnwrap(vm.upcomingDay)
        XCTAssertEqual(upcoming.petName, "小橘", "今天命中（daysUntil=0）优先于 3 天后的领养日")
        XCTAssertEqual(upcoming.kind, .birthday)
        XCTAssertEqual(upcoming.daysUntil, 0)
    }

    func testUpcomingDayIncludesMemorialEvents() throws {
        let pet = Pet(name: "小橘")
        let petRepo = InMemoryPetRepository(pets: [pet])
        let event = PetEvent(
            pet: pet, eventType: "anniversary",
            eventDate: localDate(2024, 8, 25), title: "第一次见面")
        try? petRepo.addEvent(event, to: pet)
        let vm = HomeViewModel(
            photoRepository: InMemoryPhotoRepository(),
            petRepository: petRepo,
            now: { self.localNow }
        )
        vm.load()

        let upcoming = try XCTUnwrap(vm.upcomingDay)
        XCTAssertEqual(upcoming.kind, .memorial)
        XCTAssertEqual(upcoming.title, "第一次见面")
        XCTAssertEqual(upcoming.daysUntil, 8)
    }

    func testUpcomingDayCarriesPetThumbnail() {
        let pet = Pet(name: "小橘", birthday: localDate(2020, 8, 20))
        let photos = [
            Photo(uri: "test://a", pet: pet, takenAt: utcDate(2026, 8, 1), thumbnailPath: "thumb://a"),
            Photo(uri: "test://b", pet: pet, takenAt: utcDate(2026, 7, 1), thumbnailPath: ""),
        ]
        let vm = makeVM(pets: [pet], photos: photos, now: { self.localNow })
        vm.load()

        XCTAssertEqual(vm.upcomingDay?.thumbnailPath, "thumb://a", "取归属宠物最新一张照片的缩略图")

        // 无归属照片时缩略图为 nil（空串不外露）
        let bare = makeVM(pets: [pet], now: { self.localNow })
        bare.load()
        XCTAssertNil(bare.upcomingDay?.thumbnailPath)
    }
}
