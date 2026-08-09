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

    // MARK: - 内部缓存

    private var allEntries: [TimelineEntry] = []

    private let petRepo: any PetRepositoryProtocol
    private let photoRepo: any PhotoRepositoryProtocol

    init(petRepo: any PetRepositoryProtocol, photoRepo: any PhotoRepositoryProtocol) {
        self.petRepo = petRepo
        self.photoRepo = photoRepo
    }

    // MARK: - 加载

    func load(now: Date = Date(), isPro: Bool = false) {
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
                TimelinePetEvent(id: ev.id, petID: p.id, eventType: ev.eventType,
                                 eventDate: ev.eventDate, title: ev.title)
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
        hasLockedHistory = TimelineAccessLogic.hasLockedHistory(entries, now: now, isPro: isPro)
        allEntries = TimelineAccessLogic.visibleEntries(entries, now: now, isPro: isPro)
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

    // MARK: - 查询

    /// 全部条目数（不受筛选影响，供标题栏统计用）。
    var totalCount: Int { allEntries.count }

    /// 当前筛选后条目数。
    var filteredCount: Int { months.reduce(0) { $0 + $1.entries.count } }
}
