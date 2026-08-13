import Foundation

// RedPacketDraft — 红包封面草稿模型（对应红包封面开发计划 §5）。
//
// 草稿保存为可恢复的 JSON，而不是只保存最终 PNG。
// 资源保存为文件路径或资源 ID，抠图保存为 matte/mask 路径，
// 不把 CGImage/UIImage 或大位图写入 SwiftData。

/// 红包封面草稿。
public struct RedPacketCoverDraft: Codable, Equatable, Identifiable, Sendable {
    /// 草稿唯一标识。
    public var id: UUID
    /// 使用的模板 ID。
    public var templateID: String
    /// 模板版本号。
    public var templateRevision: Int
    /// 来源照片 ID（可选）。
    public var sourcePhotoID: UUID?
    /// 图层集合。
    public var layers: [RedPacketLayer]
    /// 宠物名称。
    public var petName: String
    /// 封面标题。
    public var coverTitle: String
    /// 创建时间。
    public var createdAt: Date
    /// 更新时间。
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        templateID: String,
        templateRevision: Int,
        sourcePhotoID: UUID? = nil,
        layers: [RedPacketLayer] = [],
        petName: String = "",
        coverTitle: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.templateID = templateID
        self.templateRevision = templateRevision
        self.sourcePhotoID = sourcePhotoID
        self.layers = layers
        self.petName = petName
        self.coverTitle = coverTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - JSON 编解码

    /// 编码为 JSON Data。
    public func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// 从 JSON Data 解码。
    public static func decodeJSON(_ data: Data) throws -> RedPacketCoverDraft {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RedPacketCoverDraft.self, from: data)
    }

    // MARK: - 工厂

    /// 从模板创建新草稿。
    public static func create(
        from template: RedPacketTemplate,
        sourcePhotoID: UUID? = nil,
        petName: String = ""
    ) -> RedPacketCoverDraft {
        let layers = rpDefaultLayers(for: template, petName: petName)
        return RedPacketCoverDraft(
            templateID: template.id,
            templateRevision: template.revision,
            sourcePhotoID: sourcePhotoID,
            layers: layers,
            petName: petName,
            coverTitle: petName.isEmpty ? "恭喜发财" : petName
        )
    }
}
