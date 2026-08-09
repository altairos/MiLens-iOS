//  PhotoRepository —— 照片数据访问（对应源端 repository/PhotoRepository.ets）。
//  扫描/导入边界（DESIGN.md §7）：扫描只调用 getAllOriginalURIs() 做去重，
//  入库唯一路径是用户主动触发的 insertPhoto()。
//  去重键是 originalURI（Photos localIdentifier）——uri 是沙盒副本路径，
//  每次导入由 ImportService 以 UUID 文件名生成，不能与系统库 identifier 比较（P0 修复）。

import Foundation
import SwiftData

/// 重复标记组（对应源端 `DuplicateMarkGroup`）。
/// `replaceDuplicateMarks` 用此结构原子替换所有重复关系。
struct DuplicateMarkGroup: Equatable, Sendable {
    let bestID: UUID
    let duplicateIDs: [UUID]
}

/// 照片仓储协议（@MainActor —— SwiftData ModelContext 隔离）。
@MainActor
protocol PhotoRepositoryProtocol {
    func getPhoto(id: UUID) throws -> Photo?
    func getPhotoByURI(_ uri: String) throws -> Photo?
    /// 按系统原图 URI（originalURI，Photos localIdentifier）查询——扫描/导入去重主键。
    func getPhotoByOriginalURI(_ originalURI: String) throws -> Photo?
    /// 已入库的所有原图 URI（扫描/导入去重用——对应源端 getAllPhotoUris）。
    func getAllOriginalURIs() throws -> Set<String>
    /// 已入库的所有 URI（沙盒副本路径集合，兼容旧调用方）。
    func getAllPhotoURIs() throws -> Set<String>
    /// 照片总数（H2：替代 getAllPhotoURIs().count 的全表计数）。
    func countAllPhotos() throws -> Int
    /// 相册分页（按拍摄时间倒序，对应源端 getPhotosPage）。
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo]
    /// 某宠物的全部照片（对应源端 getPhotosByPetId）。
    func getPhotosByPet(_ pet: Pet) throws -> [Photo]
    /// 未分配宠物的照片（档案「待整理」分类来源，UI-DESIGN.md §6.4；按拍摄时间倒序）。
    func getUnassignedPhotos(limit: Int) throws -> [Photo]
    /// 指定月日拍摄、参与纪念事件的照片（对应源端 getAnniversaryEvents）。
    /// - Parameters:
    ///   - month: 1–12
    ///   - day: 1–31
    ///   - excludeYear: 排除指定年份的照片（时光机用，nil = 不排除）
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo]
    /// 用户主动导入——唯一入库路径（DESIGN.md §7 硬约束）。
    func insertPhoto(_ photo: Photo) throws
    /// 用户主动导入（批量）——一次事务写入多张（批量导入用，避免逐张 save）。
    func insertPhotos(_ photos: [Photo]) throws
    func deletePhoto(_ photo: Photo) throws
    /// 持久化已修改的照片属性（编辑回写用——uri/尺寸/文件大小等已就地更新）。
    func updatePhoto(_ photo: Photo) throws
    /// 分配/取消归属（对应源端 assignPhotoToPet）。
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws
    func setFavorite(_ photo: Photo, favorite: Bool) throws
    func updateNote(_ photo: Photo, note: String) throws

    // ── 质量评分 / 重复分组（ADR-0008）──
    /// 质量评分待处理的照片（qualityScore == 0），按 createdAt 升序（对应源端 `getPendingQualityScorePage`）。
    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo]
    /// 重复分析候选（phash 非空），按 createdAt 升序（对应源端 `getDuplicateCandidates`）。
    func getDuplicateCandidates() throws -> [Photo]
    /// 更新照片质量数据（对应源端 `updateQualityScore`，扩展为同时写入 phash）。
    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws
    /// 原子替换所有重复标记（对应源端 `replaceDuplicateMarks`）。
    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws
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

    func getPhotoByOriginalURI(_ originalURI: String) throws -> Photo? {
        let descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.originalURI == originalURI }
        )
        return try context.fetch(descriptor).first
    }

    func getAllOriginalURIs() throws -> Set<String> {
        // H2 分页化：只取 originalURI 一列，避免全表 Photo 整行 faulting（大图库 5000+）
        var descriptor = FetchDescriptor<Photo>()
        descriptor.propertiesToFetch = [\Photo.originalURI]
        let photos = try context.fetch(descriptor)
        return Set(photos.map(\.originalURI))
    }

    func getAllPhotoURIs() throws -> Set<String> {
        // H2 分页化：只取 uri 一列，避免全表 Photo 整行 faulting（孤儿审计/计数路径）
        var descriptor = FetchDescriptor<Photo>()
        descriptor.propertiesToFetch = [\Photo.uri]
        let photos = try context.fetch(descriptor)
        return Set(photos.map(\.uri))
    }

    func countAllPhotos() throws -> Int {
        // fetchCount 只回行数，不物化任何对象（替代 getAllPhotoURIs().count）
        try context.fetchCount(FetchDescriptor<Photo>())
    }

    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] {
        var descriptor = FetchDescriptor<Photo>(
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func getPhotosByPet(_ pet: Pet) throws -> [Photo] {
        // 用已加载的关系排序，避免可选关系 predicate 的不确定性。
        return pet.photos.sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
    }

    func getUnassignedPhotos(limit: Int) throws -> [Photo] {
        var descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.pet == nil },
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        return try context.fetch(descriptor)
    }

    /// 指定月日拍摄、参与纪念事件的照片（对应源端 `getAnniversaryEvents`）。
    /// 过滤语义：eventNotify = true、note 非空、拍摄日期 MM-DD 匹配、可选排除年份；
    /// 按拍摄时间倒序。
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo] {
        var descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.eventNotify },
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        // SwiftData 谓词无法表达月日匹配，先取 eventNotify 子集再内存过滤
        // （与 getDuplicateCandidates 同模式，量级可控）。
        let photos = try context.fetch(descriptor)
        return photos.filter { photo in
            guard !photo.note.isEmpty,
                  NotifyCheckLogic.matchesMonthDay(photo.takenAt, month: month, day: day) else {
                return false
            }
            if let excludeYear,
               NotifyCheckLogic.isInYear(photo.takenAt, year: excludeYear) {
                return false
            }
            return true
        }
    }

    func insertPhoto(_ photo: Photo) throws {
        context.insert(photo)
        try context.save()
    }

    func insertPhotos(_ photos: [Photo]) throws {
        for photo in photos { context.insert(photo) }
        try context.save()
    }

    func deletePhoto(_ photo: Photo) throws {
        context.delete(photo)
        try context.save()
    }

    func updatePhoto(_ photo: Photo) throws {
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

    // MARK: - 质量评分 / 重复分组

    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo] {
        var descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.qualityScore == 0 },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func getDuplicateCandidates() throws -> [Photo] {
        var descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { !$0.phash.isEmpty },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        // H2：只取分组算法所需的列（QualityScorer.findDuplicates 的投影字段）
        descriptor.propertiesToFetch = [
            \Photo.id, \Photo.phash, \Photo.qualityScore, \Photo.sharpness,
            \Photo.width, \Photo.height, \Photo.fileSize,
        ]
        return try context.fetch(descriptor)
    }

    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws {
        photo.sharpness = sharpness
        photo.qualityScore = qualityScore
        if !phash.isEmpty { photo.phash = phash }
        try context.save()
    }

    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws {
        // 先清除所有标记（源端 SQL 原子 UPDATE 的等价语义）
        let all = try context.fetch(FetchDescriptor<Photo>())
        for photo in all {
            photo.duplicateOf = nil
            photo.isBest = true
        }
        // 再写入分组关系
        var duplicateToBest: [UUID: UUID] = [:]
        for group in groups {
            for dupID in group.duplicateIDs {
                duplicateToBest[dupID] = group.bestID
            }
        }
        for photo in all {
            if let bestID = duplicateToBest[photo.id] {
                photo.duplicateOf = bestID
                photo.isBest = false
            }
        }
        try context.save()
    }
}
