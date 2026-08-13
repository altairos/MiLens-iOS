//  InMemoryRepositories —— 纯内存仓储共享实现（PhotoRepositoryProtocol / PetRepositoryProtocol）。
//
//  供各 ViewModel/Service 测试复用（SettingsViewModelTests 等依赖 internal 可见性）。
//  实现为各文件历史 private 版的语义超集：
//  - getAnniversaryPhotos：纪念日过滤（NotifyServiceTests 时光机用例）
//  - updatePhoto：记录 updatedPhoto（EditorViewModelTests 回写断言）
//  - updateFeatureData：写入 featureData（PetMatcherTests 特征注册断言）
//  各测试均以空数据构造，行为与历史 private 版一致。

import Foundation
@testable import MiLens

/// 内存照片仓储。
@MainActor
final class InMemoryPhotoRepository: PhotoRepositoryProtocol {
    /// 历史 private 版语义超集（EditorViewModelTests 需读 photos 断言回写）。
    private(set) var photos: [Photo]
    private(set) var updatedPhoto: Photo?

    init(photos: [Photo] = []) {
        self.photos = photos
    }

    func getPhoto(id: UUID) throws -> Photo? { photos.first { $0.id == id } }
    func getPhotoByURI(_ uri: String) throws -> Photo? { photos.first { $0.uri == uri } }
    func getPhotoByOriginalURI(_ originalURI: String) throws -> Photo? { photos.first { $0.originalURI == originalURI } }
    func getAllOriginalURIs() throws -> Set<String> { Set(photos.map(\.originalURI)) }
    func getAllPhotoURIs() throws -> Set<String> { Set(photos.map(\.uri)) }
    func countAllPhotos() throws -> Int { photos.count }
    func getLatestPhotoDate() throws -> Date? { photos.map(\.createdAt).max() }
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] {
        Array(photos.sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }.dropFirst(offset).prefix(limit))
    }
    func getPhotosByPet(_ pet: Pet) throws -> [Photo] {
        photos.filter { $0.pet?.id == pet.id }
    }
    func getUnassignedPhotos(limit: Int) throws -> [Photo] {
        Array(photos.filter { $0.pet == nil }
            .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
            .prefix(max(0, limit)))
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
    func insertPhotos(_ photos: [Photo]) throws { self.photos.append(contentsOf: photos) }
    func deletePhoto(_ photo: Photo) throws { photos.removeAll { $0.id == photo.id } }
    func updatePhoto(_ photo: Photo) throws { updatedPhoto = photo }
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws {
        // 维护双向关系（SwiftData @Model 自动维护，mock 需手动）
        if let oldPet = photo.pet {
            oldPet.photos.removeAll { $0.id == photo.id }
        }
        photo.pet = pet
        if let pet {
            if !pet.photos.contains(where: { $0.id == photo.id }) {
                pet.photos.append(photo)
            }
        }
    }
    func batchAssignPhotos(_ photos: [Photo], to targetPet: Pet?) throws -> [Pet] {
        // 收集受影响宠物（旧归属 + 目标归属），变更前捕获旧宠物引用
        var affectedPets: [Pet] = []
        var seenIDs = Set<UUID>()
        for photo in photos {
            if let oldPet = photo.pet, !seenIDs.contains(oldPet.id) {
                affectedPets.append(oldPet)
                seenIDs.insert(oldPet.id)
            }
        }
        if let targetPet, !seenIDs.contains(targetPet.id) {
            affectedPets.append(targetPet)
            seenIDs.insert(targetPet.id)
        }
        // 变更所有照片归属（维护双向关系，与 assignPhoto 一致）
        for photo in photos {
            if let oldPet = photo.pet {
                oldPet.photos.removeAll { $0.id == photo.id }
            }
            photo.pet = targetPet
            if let targetPet {
                if !targetPet.photos.contains(where: { $0.id == photo.id }) {
                    targetPet.photos.append(photo)
                }
            }
        }
        // 刷新所有受影响宠物的 photoCount（与 InMemoryPetRepository.refreshPhotoCount 一致）
        for pet in affectedPets {
            pet.photoCount = pet.photos.count
        }
        return affectedPets
    }
    func setFavorite(_ photo: Photo, favorite: Bool) throws { photo.isFavorite = favorite }
    func updateNote(_ photo: Photo, note: String) throws { photo.note = note }
    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo] { [] }
    func getDuplicateCandidates() throws -> [Photo] { [] }
    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws {}
    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws {}
}

/// 内存宠物仓储。
@MainActor
final class InMemoryPetRepository: PetRepositoryProtocol {
    private var pets: [Pet]

    init(pets: [Pet] = []) {
        self.pets = pets
    }

    func getAllPets() throws -> [Pet] { pets }
    func getPet(id: UUID) throws -> Pet? { pets.first { $0.id == id } }
    func insertPet(_ pet: Pet) throws { pets.append(pet) }
    func updatePet(_ pet: Pet) throws {}
    func deletePet(_ pet: Pet) throws { pets.removeAll { $0.id == pet.id } }
    func refreshPhotoCount(for pet: Pet) throws {
        // 与 SwiftDataPetRepository 一致：基于 photos 关系重新计数
        pet.photoCount = pet.photos.count
    }
    func updateFeatureData(_ pet: Pet, data: Data?) throws { pet.featureData = data }
    func addEvent(_ event: PetEvent, to pet: Pet) throws {
        // 维护双向关系（SwiftData @Model 自动维护，mock 需手动）
        event.pet = pet
        if !pet.events.contains(where: { $0.id == event.id }) {
            pet.events.append(event)
        }
    }
}
