//  PhotoRepository —— 照片数据访问（对应源端 repository/PhotoRepository.ets）。
//  扫描/导入边界（DESIGN.md §7）：扫描只调用 getAllPhotoURIs() 做去重，
//  入库唯一路径是用户主动触发的 insertPhoto()。

import Foundation
import SwiftData

/// 照片仓储协议（@MainActor —— SwiftData ModelContext 隔离）。
@MainActor
protocol PhotoRepositoryProtocol {
    func getPhoto(id: UUID) throws -> Photo?
    func getPhotoByURI(_ uri: String) throws -> Photo?
    /// 已入库的所有 URI（扫描去重用——对应源端 getAllPhotoUris）。
    func getAllPhotoURIs() throws -> Set<String>
    /// 相册分页（按拍摄时间倒序，对应源端 getPhotosPage）。
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo]
    /// 某宠物的全部照片（对应源端 getPhotosByPetId）。
    func getPhotosByPet(_ pet: Pet) throws -> [Photo]
    /// 用户主动导入——唯一入库路径（DESIGN.md §7 硬约束）。
    func insertPhoto(_ photo: Photo) throws
    func deletePhoto(_ photo: Photo) throws
    /// 分配/取消归属（对应源端 assignPhotoToPet）。
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws
    func setFavorite(_ photo: Photo, favorite: Bool) throws
    func updateNote(_ photo: Photo, note: String) throws
}

/// SwiftData 实现的照片仓储。
@MainActor
final class SwiftDataPhotoRepository: PhotoRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func getPhoto(id: UUID) throws -> Photo? {
        let descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func getPhotoByURI(_ uri: String) throws -> Photo? {
        let descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.uri == uri }
        )
        return try context.fetch(descriptor).first
    }

    func getAllPhotoURIs() throws -> Set<String> {
        let descriptor = FetchDescriptor<Photo>()
        let photos = try context.fetch(descriptor)
        return Set(photos.map(\.uri))
    }

    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] {
        let descriptor = FetchDescriptor<Photo>(
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func getPhotosByPet(_ pet: Pet) throws -> [Photo] {
        let petID = pet.id
        let descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.pet?.id == petID },
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func insertPhoto(_ photo: Photo) throws {
        context.insert(photo)
        try context.save()
    }

    func deletePhoto(_ photo: Photo) throws {
        context.delete(photo)
        try context.save()
    }

    func assignPhoto(_ photo: Photo, to pet: Pet?) throws {
        photo.pet = pet
        try context.save()
    }

    func setFavorite(_ photo: Photo, favorite: Bool) throws {
        photo.isFavorite = favorite
        try context.save()
    }

    func updateNote(_ photo: Photo, note: String) throws {
        photo.note = note
        try context.save()
    }
}
