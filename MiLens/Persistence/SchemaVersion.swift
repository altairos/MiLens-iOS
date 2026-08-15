//  Schema 版本与迁移计划（DESIGN.md §7）。
//
//  ⚠️ 版本纪律：V1 已冻结（2026-08），V2 追加 PetEvent 字段（body/sourceType/isPinned/relatedPhotoID）。
//  后续任何字段/关系变更必须：定义 SchemaV3（版本号 3.x）+ 追加 MigrationStage；
//  绝不允许改动已冻结版本的定义后保持版本号不变（会导致存量库打开失败）。
//
//  冻结机制：每个 VersionedSchema 持有**独立的冻结模型类型**（嵌套 @Model class），
//  而非引用运行时的当前 @Model。这样旧版本定义一经冻结即与后续模型演进解耦——
//  即使顶层 Pet/Photo/PetEvent 继续增删字段，SchemaV1.Pet/Photo/PetEvent 仍保持
//  V1 时刻的字段快照。SwiftData 按实体名（类名末段）跨版本映射，lightweight
//  migration 处理纯新增可空/有默认值字段。这是 Apple 推荐的 VersionedSchema 写法
//  （见 SampleTrips）。
//
//  迁移策略（正式决策，2026-08）：
//  - 产品尚未发布，V1.0 首发前清除所有旧开发数据库（删除 App 重装）——
//    这是正式的首发策略，不是临时规避。理由：SwiftData 对「新增唯一约束」
//    不支持 lightweight migration；P0 修复前创建的开发库（无 originalURI unique）
//    与 V1 模型不兼容，custom migration 无法可靠重建其内部 unique index。
//  - V1 → V2：纯新增可空/有默认值字段，SwiftData lightweight migration 自动处理。
//  - 首发后任何 schema 变更：递增 SchemaV3（版本号 3.x）并追加 MigrationStage。
//  - 测试一律使用 in-memory 容器（SchemaV2），不依赖迁移路径。
//  - V1→V2 迁移的最终验证须在 Mac 上用真实旧库确认（本机环境无法跑 SwiftData 运行时）。

import Foundation
import SwiftData

/// Schema V1 —— MiLens 初始数据模型（Pet / Photo / PetEvent，含 originalURI 唯一约束）。
/// 已冻结：持有独立嵌套模型类型，勿改定义。
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SchemaV1.Pet.self, SchemaV1.Photo.self, SchemaV1.PetEvent.self]
    }

    // MARK: - V1 Pet（字段快照，与顶层 Pet 的 V1 时刻一致）

    @Model
    final class Pet {
        @Attribute(.unique) var id: UUID
        var name: String
        var species: Species
        var breed: String
        var gender: Gender
        var birthday: Date?
        var adoptionDay: Date?
        var avatarPath: String
        var notes: String
        var featureData: Data?
        var photoCount: Int
        var createdAt: Date
        var updatedAt: Date

        @Relationship(deleteRule: .cascade, inverse: \PetEvent.pet)
        var events: [PetEvent]

        @Relationship(deleteRule: .nullify, inverse: \Photo.pet)
        var photos: [Photo]

        init(
            id: UUID = UUID(),
            name: String,
            species: Species = .unknown,
            breed: String = "",
            gender: Gender = .unknown,
            birthday: Date? = nil,
            adoptionDay: Date? = nil,
            avatarPath: String = "",
            notes: String = "",
            featureData: Data? = nil,
            photoCount: Int = 0,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.name = name
            self.species = species
            self.breed = breed
            self.gender = gender
            self.birthday = birthday
            self.adoptionDay = adoptionDay
            self.avatarPath = avatarPath
            self.notes = notes
            self.featureData = featureData
            self.photoCount = photoCount
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.events = []
            self.photos = []
        }
    }

    // MARK: - V1 Photo（字段快照）

    @Model
    final class Photo {
        @Attribute(.unique) var id: UUID
        var uri: String
        @Attribute(.unique) var originalURI: String
        var pet: Pet?
        var takenAt: Date?
        var latitude: Double
        var longitude: Double
        var placeName: String
        var thumbnailPath: String
        var note: String
        var isFavorite: Bool
        var eventNotify: Bool
        var width: Int
        var height: Int
        var fileSize: Int64
        var category: String
        var subCategory: String
        var createdAt: Date
        var phash: String
        var sharpness: Double
        var qualityScore: Double
        var duplicateOf: UUID?
        var isBest: Bool

        init(
            id: UUID = UUID(),
            uri: String,
            originalURI: String = "",
            pet: Pet? = nil,
            takenAt: Date? = nil,
            latitude: Double = 0,
            longitude: Double = 0,
            placeName: String = "",
            thumbnailPath: String = "",
            note: String = "",
            isFavorite: Bool = false,
            eventNotify: Bool = true,
            width: Int = 0,
            height: Int = 0,
            fileSize: Int64 = 0,
            category: String = "unknown",
            subCategory: String = "other",
            createdAt: Date = Date(),
            phash: String = "",
            sharpness: Double = 0,
            qualityScore: Double = 0,
            duplicateOf: UUID? = nil,
            isBest: Bool = true
        ) {
            self.id = id
            self.uri = uri
            self.originalURI = originalURI.isEmpty ? uri : originalURI
            self.pet = pet
            self.takenAt = takenAt
            self.latitude = latitude
            self.longitude = longitude
            self.placeName = placeName
            self.thumbnailPath = thumbnailPath
            self.note = note
            self.isFavorite = isFavorite
            self.eventNotify = eventNotify
            self.width = width
            self.height = height
            self.fileSize = fileSize
            self.category = category
            self.subCategory = subCategory
            self.createdAt = createdAt
            self.phash = phash
            self.sharpness = sharpness
            self.qualityScore = qualityScore
            self.duplicateOf = duplicateOf
            self.isBest = isBest
        }
    }

    // MARK: - V1 PetEvent（不含 V2 新增的 body/sourceType/isPinned/relatedPhotoID）

    @Model
    final class PetEvent {
        @Attribute(.unique) var id: UUID
        var pet: Pet?
        var eventType: String
        var eventDate: Date
        var title: String
        var notify: Bool

        init(
            id: UUID = UUID(),
            pet: Pet? = nil,
            eventType: String,
            eventDate: Date,
            title: String,
            notify: Bool = true
        ) {
            self.id = id
            self.pet = pet
            self.eventType = eventType
            self.eventDate = eventDate
            self.title = title
            self.notify = notify
        }
    }
}

/// Schema V2 —— 扩展 PetEvent（body/sourceType/isPinned/relatedPhotoID）。
/// 运行时当前 schema：引用顶层 @Model（Pet/Photo/PetEvent），App 与测试直接使用这些类型。
/// 纯新增可空字段，lightweight migration 自动处理。
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Pet.self, Photo.self, PetEvent.self]
    }
}

/// 迁移计划——V1 → V2（lightweight），后续版本按序追加 stage。
/// 实体按类名末段跨版本映射（SchemaV1.PetEvent → "PetEvent" → 顶层 PetEvent），
/// V2 仅新增带默认值字段，SwiftData 自动 lightweight migration。
enum MiLensMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        // V1 → V2：PetEvent 纯新增字段（body/sourceType/isPinned/relatedPhotoID，均有默认值），
        // Pet/Photo 字段不变。SwiftData lightweight migration 自动处理。
        // 最终须在 Mac 上用真实旧库验证（见文件头注释）。
        [MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
