//  HomeViewModel —— 首页数据编排层。
//
//  首页视觉只消费这个快照，不直接拼装 SwiftData 查询。选片、问候和回忆
//  规则由 MiLensKit 纯逻辑负责；本层只做仓储读取、实体投影和可展示状态。

import Foundation
import MiLensKit
import Observation

@MainActor
@Observable
final class HomeViewModel {
    struct MemoryItem: Identifiable {
        let id: UUID
        let entry: HomeMemoryEntry
        let photo: Photo
    }

    var photos: [Photo] = []
    var pets: [Pet] = []
    var memoryItems: [MemoryItem] = []
    var isLoading = true
    var loadError: String?

    private let photoRepository: any PhotoRepositoryProtocol
    private let petRepository: any PetRepositoryProtocol
    private let now: () -> Date

    init(
        photoRepository: any PhotoRepositoryProtocol,
        petRepository: any PetRepositoryProtocol,
        now: @escaping () -> Date = Date.init
    ) {
        self.photoRepository = photoRepository
        self.petRepository = petRepository
        self.now = now
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: now())
        return HomeGreetingLogic.greeting(forHour: hour)
    }

    var heroPhoto: Photo? {
        let projections = photos.map {
            HomeHeroPhoto(id: $0.id, takenAt: $0.takenAt, petID: $0.pet?.id)
        }
        guard let selected = HomeHeroLogic.selectHeroPhoto(projections, now: now()) else {
            return nil
        }
        return photos.first { $0.id == selected.id }
    }

    var heroIsToday: Bool {
        guard let heroPhoto else { return false }
        return HomeHeroLogic.isToday(takenAt: heroPhoto.takenAt, now: now())
    }

    var heroCaption: String {
        HomeHeroLogic.buildHeroCaption(
            petName: heroPhoto?.pet?.name,
            isToday: heroIsToday
        )
    }

    func load() {
        isLoading = true
        loadError = nil

        do {
            // 首页只需要最近一批照片，同时覆盖回忆区；不会把整个图库读入内存。
            photos = try photoRepository.getPhotosPage(offset: 0, limit: 500)
            pets = try petRepository.getAllPets()

            let photoProjections = photos.map {
                HomeMemoryPhoto(id: $0.id, takenAt: $0.takenAt, note: $0.note, petID: $0.pet?.id)
            }
            let petProjections = pets.map { HomeMemoryPet(id: $0.id, name: $0.name) }
            let entries = HomeMemoryLogic.selectMemoryPhotos(
                photoProjections,
                now: now(),
                pets: petProjections
            )
            memoryItems = entries.compactMap { entry in
                guard let photo = photos.first(where: { $0.id == entry.photoID }) else { return nil }
                return MemoryItem(id: entry.photoID, entry: entry, photo: photo)
            }
        } catch {
            photos = []
            pets = []
            memoryItems = []
            loadError = String(localized: "home.loadError")
        }

        isLoading = false
    }
}
