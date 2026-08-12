//  WidgetIntents —— WidgetKit App Intents 配置（WidgetKit-Design.md §6.3）。
//
//  桌面组件使用 AppIntentConfiguration：用户只配置「伙伴」与「内容类型」。
//  - SelectPetIntent：全部伙伴或指定伙伴。
//  - PhotoEchoSource：今日/往日回忆、最近照片、最近拼豆作品。
//
//  动态选项从共享快照读取（不打开 SwiftData store）。

import AppIntents
import WidgetKit
import MiLensKit

// MARK: - 宠物实体

/// 可配置的伙伴选项（全部伙伴 或 指定一只）。
struct PetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "伙伴"
    static var defaultQuery = PetEntityQuery()

    let id: String           // "all" 或 UUID 字符串
    let displayName: String  // 「全部伙伴」/「小橘」

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }

    /// 转换为 WidgetSelectionLogic 所需的 petID（nil = 全部伙伴）。
    var petID: UUID? {
        id == "all" ? nil : UUID(uuidString: id)
    }
}

// MARK: - 宠物查询

/// 从共享快照读取宠物列表供用户选择。
struct PetEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PetEntity] {
        let all = allEntities()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [PetEntity] {
        allEntities()
    }

    func defaultResult() async -> PetEntity {
        PetEntity(id: "all", displayName: "全部伙伴")
    }

    /// 从快照读取全部宠物 + 「全部伙伴」选项。
    private func allEntities() -> [PetEntity] {
        var entities: [PetEntity] = [PetEntity(id: "all", displayName: "全部伙伴")]
        if let snapshot = WidgetSnapshotReader.read() {
            entities.append(contentsOf: snapshot.pets.map {
                PetEntity(id: $0.id.uuidString, displayName: $0.name)
            })
        }
        return entities
    }
}

// MARK: - 选择伙伴 Intent

/// 选择 Widget 展示的伙伴（全部 或 指定一只）。
struct SelectPetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "选择伙伴"
    static var description = IntentDescription("选择这个 Widget 展示的伙伴档案")

    @Parameter(title: "伙伴", default: PetEntity(id: "all", displayName: "全部伙伴"))
    var pet: PetEntity

    init() {}
    init(pet: PetEntity) {
        self.pet = pet
    }
}

// MARK: - 相片回声配置 Intent

/// 相片回声 Widget 的完整配置（伙伴 + 内容源）。
struct PhotoEchoConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "相片回声设置"
    static var description = IntentDescription("选择展示哪个伙伴的哪类照片")

    @Parameter(title: "伙伴", default: PetEntity(id: "all", displayName: "全部伙伴"))
    var pet: PetEntity

    @Parameter(title: "内容", default: PhotoEchoSourceAppEnum.todayOrRecent)
    var source: PhotoEchoSourceAppEnum

    init() {}
    init(pet: PetEntity, source: PhotoEchoSourceAppEnum) {
        self.pet = pet
        self.source = source
    }
}

/// PhotoEchoSource 的 AppEnum 桥（AppIntents 需要 AppEnum，不能直接用 String enum）。
enum PhotoEchoSourceAppEnum: String, AppEnum, CaseIterable {
    case todayOrRecent
    case yearsAgoToday
    case recentWork

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "内容来源"
    static var caseDisplayRepresentations: [PhotoEchoSourceAppEnum: DisplayRepresentation] = [
        .todayOrRecent: "今日 / 最近",
        .yearsAgoToday: "往日回忆",
        .recentWork: "最近作品",
    ]

    /// 转换为 MiLensKit 的 PhotoEchoSource。
    var toLogic: PhotoEchoSource {
        PhotoEchoSource(rawValue: rawValue) ?? .todayOrRecent
    }
}
