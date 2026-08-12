import XCTest
@testable import MiLensKit

//  WidgetSelectionLogic 纯决策逻辑测试。
//
//  覆盖 WidgetKit-Design.md §3-§4 的选片策略、纪念日排序、档案统计与状态判定。
//  无源端黄金规格（Widget 为 iOS 新增概念），行为规格由设计契约定义，本文件守护。
//  全部日期用固定 UTC Calendar（miLensUTCCalendar）构造，任意时区可复现。

// MARK: - 测试工具

private enum WidgetTestSupport {
    /// 固定「现在」：2026-08-12 12:00 UTC。
    static let now = makeDate(2026, 8, 12, 12)

    static func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return miLensUTCCalendar.date(from: comps)!
    }

    static let petA = UUID()
    static let petB = UUID()

    static func makePet(id: UUID = petA, name: String = "小橘", photoCount: Int = 5) -> PetProjection {
        PetProjection(
            id: id, name: name, species: "cat",
            birthday: makeDate(2023, 5, 1), adoptionDay: makeDate(2023, 6, 15),
            photoCount: photoCount
        )
    }

    static func makePhoto(
        id: UUID = UUID(), petID: UUID? = petA, petName: String? = "小橘",
        takenAt: Date? = nil, note: String = "", qualityScore: Double = 0.5, isWork: Bool = false
    ) -> PhotoProjection {
        PhotoProjection(
            id: id, petID: petID, petName: petName,
            thumbnailFileName: "\(id.uuidString.prefix(8)).jpg",
            takenAt: takenAt, note: note, qualityScore: qualityScore, isWork: isWork
        )
    }
}

// MARK: - 相片回声选片

final class WidgetSelectionLogicPhotoEchoTests: XCTestCase {

    func testTodayOrRecent_selectsTodayLatest() {
        let today1 = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 8, 12, 9))
        let today2 = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 8, 12, 15))
        let old = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 7, 1))
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()],
            photos: [old, today1, today2],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.selectPhotoEcho(
            snapshot: snap, petID: nil, source: .todayOrRecent, now: WidgetTestSupport.now
        )
        XCTAssertEqual(result?.id, today2.id, "应选今日最新的照片（15:00 > 9:00）")
    }

    func testTodayOrRecent_fallsBackToRecentWhenNoToday() {
        let p1 = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 7, 1), qualityScore: 0.8)
        let p2 = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 6, 1), qualityScore: 0.3)
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()],
            photos: [p2, p1],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.selectPhotoEcho(
            snapshot: snap, petID: nil, source: .todayOrRecent, now: WidgetTestSupport.now, randomIndex: 0
        )
        XCTAssertNotNil(result, "无今日照片时应回退到最近照片")
        // 回退按质量分 top 池随机；2 张照片池至少 5 张 → 全部入选，index 0 = 最高分
        XCTAssertEqual(result?.id, p1.id)
    }

    func testTodayOrRecent_returnsNilWhenPoolEmpty() {
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()], photos: [],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.selectPhotoEcho(
            snapshot: snap, petID: nil, source: .todayOrRecent, now: WidgetTestSupport.now
        )
        XCTAssertNil(result, "空照片池应返回 nil")
    }

    func testPetIDFilter_limitsToSpecificPet() {
        let photoA = WidgetTestSupport.makePhoto(petID: WidgetTestSupport.petA, takenAt: WidgetTestSupport.makeDate(2026, 8, 12))
        let photoB = WidgetTestSupport.makePhoto(petID: WidgetTestSupport.petB, petName: "小花", takenAt: WidgetTestSupport.makeDate(2026, 8, 12, 18))
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet(id: WidgetTestSupport.petA), WidgetTestSupport.makePet(id: WidgetTestSupport.petB, name: "小花")],
            photos: [photoA, photoB],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.selectPhotoEcho(
            snapshot: snap, petID: WidgetTestSupport.petA, source: .todayOrRecent, now: WidgetTestSupport.now
        )
        XCTAssertEqual(result?.id, photoA.id, "指定 petA 时只应从 petA 的照片中选")
    }

    func testYearsAgoToday_selectsHistoricalSameDay() {
        // 往年同月同日：2024-08-12
        let yearsAgo = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2024, 8, 12))
        let recent = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 8, 11))
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()],
            photos: [recent, yearsAgo],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.selectPhotoEcho(
            snapshot: snap, petID: nil, source: .yearsAgoToday, now: WidgetTestSupport.now
        )
        XCTAssertEqual(result?.id, yearsAgo.id, "应选往年同月同日的照片")
    }

    func testYearsAgoToday_fallsBackWhenNoMatch() {
        let recent = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 7, 1), qualityScore: 0.9)
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()],
            photos: [recent],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.selectPhotoEcho(
            snapshot: snap, petID: nil, source: .yearsAgoToday, now: WidgetTestSupport.now
        )
        XCTAssertNotNil(result, "无往年同日照片时应回退到最近照片")
    }

    func testRecentWork_selectsLatestWork() {
        let work1 = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 7, 1), isWork: true)
        let work2 = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 8, 1), isWork: true)
        let normal = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 8, 11), isWork: false)
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()],
            photos: [normal, work1, work2],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.selectPhotoEcho(
            snapshot: snap, petID: nil, source: .recentWork, now: WidgetTestSupport.now
        )
        XCTAssertEqual(result?.id, work2.id, "应选最近的拼豆作品")
    }

    func testRecentWork_fallsBackWhenNoWork() {
        let normal = WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.makeDate(2026, 8, 11), isWork: false)
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()],
            photos: [normal],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.selectPhotoEcho(
            snapshot: snap, petID: nil, source: .recentWork, now: WidgetTestSupport.now
        )
        XCTAssertNotNil(result, "无作品时应回退到最近照片")
    }
}

// MARK: - 纪念日

final class WidgetSelectionLogicUpcomingDayTests: XCTestCase {

    func testNextUpcomingDay_picksClosest() {
        // petA 生日 5-1（已过，明年），领养日 6-15（已过，明年）
        // petB 生日 8-15（还有 3 天）→ 应选这个
        let day1 = UpcomingDayProjection(
            kind: .birthday, petID: WidgetTestSupport.petA, petName: "小橘",
            title: "小橘的生日", originalDate: WidgetTestSupport.makeDate(2023, 5, 1)
        )
        let day2 = UpcomingDayProjection(
            kind: .adoption, petID: WidgetTestSupport.petA, petName: "小橘",
            title: "领养日", originalDate: WidgetTestSupport.makeDate(2023, 6, 15)
        )
        let day3 = UpcomingDayProjection(
            kind: .birthday, petID: WidgetTestSupport.petB, petName: "小花",
            title: "小花的生日", originalDate: WidgetTestSupport.makeDate(2020, 8, 15)
        )
        let snap = WidgetSnapshot(
            pets: [], photos: [],
            upcomingDays: [day1, day2, day3],
            archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.nextUpcomingDay(
            snapshot: snap, petID: nil, now: WidgetTestSupport.now
        )
        XCTAssertEqual(result?.day.petID, WidgetTestSupport.petB)
        XCTAssertEqual(result?.daysUntil, 3, "8-15 距 8-12 为 3 天")
    }

    func testNextUpcomingDay_todayIsZero() {
        // 今天就是纪念日
        let day = UpcomingDayProjection(
            kind: .birthday, petID: WidgetTestSupport.petA, petName: "小橘",
            title: "小橘的生日", originalDate: WidgetTestSupport.makeDate(2023, 8, 12)
        )
        let snap = WidgetSnapshot(
            pets: [], photos: [],
            upcomingDays: [day],
            archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.nextUpcomingDay(
            snapshot: snap, petID: nil, now: WidgetTestSupport.now
        )
        XCTAssertEqual(result?.daysUntil, 0, "今天就是纪念日，daysUntil=0")
        XCTAssertGreaterThan(result!.daysTogether, 0, "daysTogether 应大于 0")
    }

    func testNextUpcomingDay_petIDFilter() {
        let dayA = UpcomingDayProjection(
            kind: .birthday, petID: WidgetTestSupport.petA, petName: "小橘",
            title: "小橘的生日", originalDate: WidgetTestSupport.makeDate(2023, 12, 25)
        )
        let dayB = UpcomingDayProjection(
            kind: .birthday, petID: WidgetTestSupport.petB, petName: "小花",
            title: "小花的生日", originalDate: WidgetTestSupport.makeDate(2020, 8, 13)
        )
        let snap = WidgetSnapshot(
            pets: [], photos: [],
            upcomingDays: [dayA, dayB],
            archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        // 指定 petA，即使 petB 的纪念日更近，也只应返回 petA 的
        let result = WidgetSelectionLogic.nextUpcomingDay(
            snapshot: snap, petID: WidgetTestSupport.petA, now: WidgetTestSupport.now
        )
        XCTAssertEqual(result?.day.petID, WidgetTestSupport.petA)
    }

    func testNextUpcomingDay_returnsNilWhenEmpty() {
        let snap = WidgetSnapshot(
            pets: [], photos: [],
            upcomingDays: [],
            archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.nextUpcomingDay(
            snapshot: snap, petID: nil, now: WidgetTestSupport.now
        )
        XCTAssertNil(result)
    }
}

// MARK: - 档案统计

final class WidgetSelectionLogicArchiveStatsTests: XCTestCase {

    func testArchiveStats_allPets() {
        let stats = ArchiveStats(
            totalPhotos: 100, totalMemories: 20, totalWorks: 5,
            archiveStartDate: WidgetTestSupport.makeDate(2023, 1, 1), petCount: 2
        )
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()], photos: [],
            upcomingDays: [], archiveStats: stats, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.archiveStats(snapshot: snap, petID: nil)
        XCTAssertEqual(result.totalPhotos, 100)
        XCTAssertEqual(result.totalMemories, 20)
        XCTAssertEqual(result.petCount, 2)
    }

    func testArchiveStats_specificPet() {
        let pet = WidgetTestSupport.makePet(id: WidgetTestSupport.petA, photoCount: 10)
        let photo1 = WidgetTestSupport.makePhoto(petID: WidgetTestSupport.petA, takenAt: WidgetTestSupport.makeDate(2024, 3, 1))
        let photo2 = WidgetTestSupport.makePhoto(petID: WidgetTestSupport.petA, takenAt: WidgetTestSupport.makeDate(2023, 1, 1), isWork: true)
        let photo3 = WidgetTestSupport.makePhoto(petID: WidgetTestSupport.petB, takenAt: WidgetTestSupport.makeDate(2022, 1, 1))
        let snap = WidgetSnapshot(
            pets: [pet],
            photos: [photo1, photo2, photo3],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.archiveStats(snapshot: snap, petID: WidgetTestSupport.petA)
        XCTAssertEqual(result.totalPhotos, 10, "应取 petProjection 的 photoCount")
        XCTAssertEqual(result.totalWorks, 1, "petA 只有 1 张作品")
        XCTAssertEqual(result.petCount, 1)
        XCTAssertEqual(result.archiveStartDate, WidgetTestSupport.makeDate(2023, 1, 1))
    }
}

// MARK: - 状态判定

final class WidgetSelectionLogicStateTests: XCTestCase {

    func testResolveState_staleWhenSnapshotNil() {
        let result = WidgetSelectionLogic.resolveState(snapshot: nil, now: WidgetTestSupport.now, petID: nil)
        XCTAssertEqual(result, .stale)
    }

    func testResolveState_staleWhenSchemaMismatch() {
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()], photos: [],
            upcomingDays: [], archiveStats: .empty,
            lastUpdated: WidgetTestSupport.now, schemaVersion: 999
        )
        let result = WidgetSelectionLogic.resolveState(snapshot: snap, now: WidgetTestSupport.now, petID: nil)
        XCTAssertEqual(result, .stale)
    }

    func testResolveState_staleWhenExpired() {
        // lastUpdated 距 now 超过 6 小时
        let old = WidgetTestSupport.now.addingTimeInterval(-7 * 3600)
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()], photos: [WidgetTestSupport.makePhoto()],
            upcomingDays: [], archiveStats: .empty, lastUpdated: old
        )
        let result = WidgetSelectionLogic.resolveState(snapshot: snap, now: WidgetTestSupport.now, petID: nil)
        XCTAssertEqual(result, .stale)
    }

    func testResolveState_emptyWhenNoPets() {
        let snap = WidgetSnapshot(
            pets: [], photos: [],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.resolveState(snapshot: snap, now: WidgetTestSupport.now, petID: nil)
        XCTAssertEqual(result, .empty, "无宠物应展示 empty")
    }

    func testResolveState_emptyWhenNoPhotos() {
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()], photos: [],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.resolveState(snapshot: snap, now: WidgetTestSupport.now, petID: nil)
        XCTAssertEqual(result, .empty, "有宠物无照片应展示 empty")
    }

    func testResolveState_emptyWhenSpecificPetNotFound() {
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet(id: WidgetTestSupport.petA)], photos: [],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.resolveState(snapshot: snap, now: WidgetTestSupport.now, petID: UUID())
        XCTAssertEqual(result, .empty, "指定的宠物不存在应展示 empty")
    }

    func testResolveState_emptyWhenSpecificPetHasNoPhotos() {
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet(id: WidgetTestSupport.petA)],
            photos: [WidgetTestSupport.makePhoto(petID: WidgetTestSupport.petB)],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.resolveState(snapshot: snap, now: WidgetTestSupport.now, petID: WidgetTestSupport.petA)
        XCTAssertEqual(result, .empty, "指定宠物无照片应展示 empty")
    }

    func testResolveState_contentWhenHasData() {
        let snap = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()],
            photos: [WidgetTestSupport.makePhoto()],
            upcomingDays: [], archiveStats: .empty, lastUpdated: WidgetTestSupport.now
        )
        let result = WidgetSelectionLogic.resolveState(snapshot: snap, now: WidgetTestSupport.now, petID: nil)
        XCTAssertEqual(result, .content)
    }

    func testIsToday() {
        let today = WidgetTestSupport.makeDate(2026, 8, 12, 3)
        let yesterday = WidgetTestSupport.makeDate(2026, 8, 11, 23)
        XCTAssertTrue(WidgetSelectionLogic.isToday(takenAt: today, now: WidgetTestSupport.now))
        XCTAssertFalse(WidgetSelectionLogic.isToday(takenAt: yesterday, now: WidgetTestSupport.now))
        XCTAssertFalse(WidgetSelectionLogic.isToday(takenAt: nil, now: WidgetTestSupport.now))
    }
}

// MARK: - Codable 往返

final class WidgetSnapshotCodableTests: XCTestCase {

    func testRoundTrip() throws {
        let original = WidgetSnapshot(
            pets: [WidgetTestSupport.makePet()],
            photos: [WidgetTestSupport.makePhoto(takenAt: WidgetTestSupport.now)],
            upcomingDays: [UpcomingDayProjection(
                kind: .birthday, petID: WidgetTestSupport.petA, petName: "小橘",
                title: "生日", originalDate: WidgetTestSupport.makeDate(2023, 5, 1)
            )],
            archiveStats: ArchiveStats(
                totalPhotos: 10, totalMemories: 3, totalWorks: 1,
                archiveStartDate: WidgetTestSupport.makeDate(2023, 1, 1), petCount: 1
            ),
            lastUpdated: WidgetTestSupport.now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(original, decoded, "Codable 往返应保持数据一致")
    }

    func testEmptySnapshot() {
        XCTAssertEqual(WidgetSnapshot.empty.pets, [])
        XCTAssertEqual(WidgetSnapshot.empty.photos, [])
        XCTAssertEqual(WidgetSnapshot.empty.archiveStats.totalPhotos, 0)
        XCTAssertEqual(WidgetSnapshot.empty.schemaVersion, WidgetSharedConfig.currentSchemaVersion)
    }
}
