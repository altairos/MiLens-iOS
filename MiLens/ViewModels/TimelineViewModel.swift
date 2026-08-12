//  TimelineViewModel —— 成长时间线状态机（@Observable）。
//  持有时间线分组（months）、选中宠物筛选、加载状态。
//  决策通过 TimelineLogic 纯函数完成（DESIGN.md §4）。
//  对应源端 TimelinePage（翻译 TimelineViewModel + 页面加载编排）。

import Foundation
import os

@MainActor
@Observable
final class TimelineViewModel {

    private let logger = Logger(subsystem: "com.milens.app", category: "Timeline")

    // MARK: - 显示层状态

    var months: [TimelineMonth] = []
    var selectedPetID: UUID? = nil
    var isLoading = false
    private(set) var hasLockedHistory = false
    private(set) var isInFullHistoryPreview = false
    private(set) var previewDaysRemaining = 0
    var shouldShowPreviewReminder: Bool {
        isInFullHistoryPreview && previewDaysRemaining <= 4 && hasHistoricalEntries
    }

    // MARK: - 内部缓存

    private var allEntries: [TimelineEntry] = []
    private var hasHistoricalEntries = false

    private let petRepo: any PetRepositoryProtocol
    private let photoRepo: any PhotoRepositoryProtocol

    init(petRepo: any PetRepositoryProtocol, photoRepo: any PhotoRepositoryProtocol) {
        self.petRepo = petRepo
        self.photoRepo = photoRepo
    }

    // MARK: - 加载

    func load(now: Date = Date(), isPro: Bool = false, firstAccessDate: Date? = nil) {
        isLoading = true
        let pets: [Pet]
        do {
            pets = try petRepo.getAllPets()
        } catch {
            logger.error("load: 读取宠物列表失败（\(error.localizedDescription)）")
            pets = []
        }
        var allPhotos: [Photo] = []
        for pet in pets {
            do {
                allPhotos.append(contentsOf: try photoRepo.getPhotosByPet(pet))
            } catch {
                logger.error("load: 读取宠物照片失败（\(pet.name)，\(error.localizedDescription)）")
            }
        }

        let timelinePets = pets.map { p in
            TimelinePet(id: p.id, name: p.name, birthday: p.birthday, hasFeatureData: p.featureData != nil)
        }
        let timelineEvents = pets.flatMap { p in
            p.events.map { ev in
                TimelinePetEvent(
                    id: ev.id, petID: p.id, eventType: ev.eventType,
                    eventDate: ev.eventDate, title: ev.title,
                    body: ev.body, sourceType: ev.sourceType,
                    relatedPhotoID: ev.relatedPhotoID
                )
            }
        }
        let timelinePhotos = allPhotos.map { ph in
            TimelinePhoto(id: ph.id, petID: ph.pet?.id, takenAt: ph.takenAt,
                          note: ph.note, uri: ph.uri, thumbnailPath: ph.thumbnailPath)
        }

        let input = TimelineInput(
            pets: timelinePets, petEvents: timelineEvents,
            photoEvents: timelinePhotos, now: now
        )
        let entries = TimelineLogic.buildTimelineEntries(input)
        hasHistoricalEntries = TimelineAccessLogic.hasLockedHistory(entries, now: now, isPro: false)
        if let firstAccessDate {
            previewDaysRemaining = TimelineAccessLogic.previewDaysRemaining(now: now, firstAccessDate: firstAccessDate)
            isInFullHistoryPreview = TimelineAccessLogic.isInFullHistoryPreview(now: now, firstAccessDate: firstAccessDate)
        } else {
            previewDaysRemaining = 0
            isInFullHistoryPreview = false
        }
        hasLockedHistory = TimelineAccessLogic.hasLockedHistory(
            entries, now: now, isPro: isPro, firstAccessDate: firstAccessDate
        )
        allEntries = TimelineAccessLogic.visibleEntries(
            entries, now: now, isPro: isPro, firstAccessDate: firstAccessDate
        )
        rebuildMonths()
        isLoading = false
    }

    // MARK: - 筛选

    /// 按宠物筛选时间线（nil = 全部宠物）。对应源端 onFilterChanged → buildMonths。
    func selectPet(_ petID: UUID?) {
        selectedPetID = petID
        rebuildMonths()
    }

    private func rebuildMonths() {
        months = TimelineLogic.buildMonths(allEntries, selectedPetID: selectedPetID)
    }

    // MARK: - 添加记忆（Life-Archive-Design.md §3.3）

    /// 添加记忆的错误文案（空=无错误）。
    var addMemoryError = ""

    /// 添加一条用户记忆，写入 PetEvent（sourceType="user"）。
    /// - Parameters:
    ///   - pet: 归属宠物（必须）
    ///   - title: 标题（可空，空时视图层拦截）
    ///   - date: 记忆日期
    ///   - body: 一句话/备注（可空）
    ///   - relatedPhotoID: 关联照片（可选）
    ///   - isPinned: 是否置顶（可选）
    /// - Returns: true 表示成功（并已刷新时间线），false 表示失败（addMemoryError 已填充）。
    @discardableResult
    func addMemory(
        to pet: Pet, title: String, date: Date, body: String,
        relatedPhotoID: UUID? = nil, isPinned: Bool = false,
        now: Date = Date(), isPro: Bool = false, firstAccessDate: Date? = nil
    ) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            addMemoryError = String(localized: "timeline.addMemory.titleRequired")
            return false
        }
        let event = PetEvent(
            pet: pet,
            eventType: "custom",
            eventDate: date,
            title: trimmedTitle,
            notify: false,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceType: "user",
            isPinned: isPinned,
            relatedPhotoID: relatedPhotoID
        )
        do {
            try petRepo.addEvent(event, to: pet)
        } catch {
            logger.error("addMemory: 保存失败（\(error.localizedDescription)）")
            addMemoryError = String(localized: "timeline.addMemory.saveFailed")
            return false
        }
        addMemoryError = ""
        load(now: now, isPro: isPro, firstAccessDate: firstAccessDate)
        return true
    }

    // MARK: - 查询

    /// 某宠物的照片（按拍摄时间倒序，供「添加记忆」选择关联照片用）。
    func photos(for pet: Pet) -> [Photo] {
        (try? photoRepo.getPhotosByPet(pet)) ?? []
    }

    /// 全部条目数（不受筛选影响，供标题栏统计用）。
    var totalCount: Int { allEntries.count }

    /// 当前筛选后条目数。
    var filteredCount: Int { months.reduce(0) { $0 + $1.entries.count } }
}
