//  Photo @Model —— 照片记录（对应源端 photo_table + models/Photo.ets）。
//  V1.0 裁剪：省略 phash/embeddingBlob/sharpness/qualityScore/duplicateOf/
//  isBest/exportStatus（质量评分/重复分组/导出状态后置 V1.x）。
//  保留 V1.0 显示与回忆功能所需字段。

import Foundation
import SwiftData

@Model
final class Photo {
    @Attribute(.unique) var id: UUID
    /// 沙盒显示/分析副本路径
    var uri: String
    /// 系统媒体库或选择器返回的原图 URI（对应源端 original_uri）
    var originalURI: String
    /// 归属宠物（nil = 未分配）
    var pet: Pet?
    /// 拍摄时间（EXIF 解析，可能为 nil）
    var takenAt: Date?
    /// GPS 坐标（0,0 表示无 GPS 信息）
    var latitude: Double
    var longitude: Double
    var placeName: String
    /// 缩略图路径（网格加载用，对应源端 thumbnail_path）
    var thumbnailPath: String
    var note: String
    var isFavorite: Bool
    /// 是否参与时间线/回忆事件（对应源端 event_notify）
    var eventNotify: Bool
    /// 像素尺寸（用于宽高比显示）
    var width: Int
    var height: Int
    /// 文件字节（缓存管理）
    var fileSize: Int64
    /// 分类标签（对应源端 category/sub_category）
    var category: String
    var subCategory: String
    var createdAt: Date

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
        createdAt: Date = Date()
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
    }
}
