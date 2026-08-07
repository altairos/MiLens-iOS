//  Pet @Model —— 宠物档案（对应源端 pet_table + models/Pet.ets）。
//  iOS V1.0 从干净 schema 起步（DESIGN.md §7），字段经范围裁剪。
//  UUID 作为业务标识（对应 Route.petProfile(petID: UUID)）。

import Foundation
import SwiftData

@Model
final class Pet {
    /// 业务唯一标识（持久层主键为 SwiftData 自管 persistentModelID）
    @Attribute(.unique) var id: UUID
    var name: String
    var species: Species
    var breed: String
    var gender: Gender
    var birthday: Date?
    var adoptionDay: Date?
    var avatarPath: String
    var notes: String

    /// CLIP 视觉特征聚合向量（P1.5 AI 方案定案后填充；V1.0 为 nil）。
    /// 对应源端 feature_blob。诚实标注：V1.0 不保证有值。
    var featureData: Data?

    /// 照片计数缓存（定期由 Repository 刷新，对应源端 updatePetPhotoCount）。
    var photoCount: Int

    var createdAt: Date
    var updatedAt: Date

    /// 纪念事件（删宠物时级联删除——事件无独立意义）
    @Relationship(deleteRule: .cascade, inverse: \PetEvent.pet)
    var events: [PetEvent]

    /// 关联照片（删宠物时解除归属，不删照片——照片保留可重新分配）
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
