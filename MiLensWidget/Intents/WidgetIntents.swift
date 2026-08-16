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
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "widget.entity.pet"
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

    /// 用户未选择伙伴时 WidgetKit 使用的默认实体；同时是各 Intent
    /// `@Parameter` 省略 `default:` 后的默认值来源（值为「全部伙伴」）。
    func defaultResult() async -> PetEntity {
        PetEntity(id: "all", displayName: String(localized: "widget.intents.pet.all"))
    }

    /// 从快照读取全部宠物 + 「全部伙伴」选项。
    private func allEntities() -> [PetEntity] {
        var entities: [PetEntity] = [PetEntity(id: "all", displayName: String(localized: "widget.intents.pet.all"))]
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
    static var title: LocalizedStringResource = "widget.intents.selectPet.title"
    static var description = IntentDescription("widget.intents.selectPet.description")

    // AppEntity 参数的 default: 只接受编译期字面量（构造调用被宏拒绝），
    // 默认值改由 PetEntityQuery.defaultResult() 提供（同一「全部伙伴」）。
    @Parameter(title: "widget.entity.pet")
    var pet: PetEntity

    init() {}
    init(pet: PetEntity) {
        self.pet = pet
    }
}

// MARK: - 相片回声配置 Intent

/// 相片回声 Widget 的完整配置（伙伴 + 内容源）。
struct PhotoEchoConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.intents.photoEcho.settings.title"
    static var description = IntentDescription("widget.intents.photoEcho.settings.description")

    // AppEntity 参数的 default: 只接受编译期字面量（构造调用被宏拒绝），
    // 默认值改由 PetEntityQuery.defaultResult() 提供（同一「全部伙伴」）。
    @Parameter(title: "widget.entity.pet")
    var pet: PetEntity

    @Parameter(title: "widget.intents.photoEcho.content", default: PhotoEchoSourceAppEnum.todayOrRecent)
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

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "widget.intents.photoEcho.contentSource"
    static var caseDisplayRepresentations: [PhotoEchoSourceAppEnum: DisplayRepresentation] = [
        .todayOrRecent: "widget.intents.photoEcho.source.todayOrRecent",
        .yearsAgoToday: "widget.intents.photoEcho.source.yearsAgoToday",
        .recentWork: "widget.intents.photoEcho.source.recentWork",
    ]

    /// 转换为 MiLensKit 的 PhotoEchoSource。
    var toLogic: PhotoEchoSource {
        PhotoEchoSource(rawValue: rawValue) ?? .todayOrRecent
    }
}

// MARK: - 纪念日实体

/// 可配置的纪念日选项（自动取最近 或 指定某个具体纪念日）。
///
/// 对应 `WidgetSelectionLogic.upcomingDay` 的 dayID 参数：`id == "auto"` 时
/// 由系统按伙伴自动取最近一个；其余 id 精确点名某个纪念日。
struct AnniversaryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "widget.entity.anniversary"
    static var defaultQuery = AnniversaryEntityQuery()

    let id: String           // "auto" 或纪念日 id
    let displayName: String  // 「自动（最近）」/「小橘的生日」

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }

    /// 转换为 WidgetSelectionLogic 所需的 dayID（nil = 自动取最近）。
    var dayID: String? {
        id == "auto" ? nil : id
    }
}

/// 从共享快照读取纪念日候选供用户选择（不打开 SwiftData store）。
///
/// 通过 `@IntentParameterDependency` 读取同 Intent 中「伙伴」参数的当前值：
/// 用户选了指定伙伴时，候选列表只显示该伙伴的纪念日；选「全部伙伴」或依赖
/// 尚未就绪（系统首次渲染配置面板）时返回全部。参考 WWDC23「Explore
/// enhancements to App Intents」的 BusRouteQuery 模式。
struct AnniversaryEntityQuery: EntityQuery {
    /// 依赖 `SelectAnniversaryIntent` 的 `pet` 参数，使候选列表随伙伴选择联动。
    @IntentParameterDependency<SelectAnniversaryIntent>(\.$pet)
    var selectAnniversaryIntent

    func entities(for identifiers: [String]) async throws -> [AnniversaryEntity] {
        let all = allEntities()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [AnniversaryEntity] {
        // 依赖未就绪（系统首次渲染）或用户选「全部伙伴」时，返回全部候选。
        // `pet.petID == nil` 表示「全部伙伴」。
        suggestedEntities(petID: selectAnniversaryIntent?.pet.petID)
    }

    /// 用户未选择纪念日时的默认实体（自动取最近），也是
    /// `@Parameter` 省略 `default:` 后的默认值来源。
    func defaultResult() async -> AnniversaryEntity {
        AnniversaryEntity(id: "auto", displayName: String(localized: "widget.intents.anniversary.auto"))
    }

    /// 「自动（最近）」选项 + 按伙伴过滤后的纪念日候选。
    /// `petID == nil` 表示「全部伙伴」，返回全部候选。
    private func suggestedEntities(petID: UUID?) -> [AnniversaryEntity] {
        var entities: [AnniversaryEntity] = [
            AnniversaryEntity(id: "auto", displayName: String(localized: "widget.intents.anniversary.auto"))
        ]
        guard let snapshot = WidgetSnapshotReader.read() else { return entities }

        let candidates = petID == nil
            ? snapshot.upcomingDays
            : snapshot.upcomingDays.filter { $0.petID == petID }
        entities.append(contentsOf: candidates.map {
            AnniversaryEntity(id: $0.id, displayName: Self.displayTitle($0))
        })
        return entities
    }

    /// 所有可选纪念日（含「自动」），不受伙伴过滤。用于 `entities(for:)` 的 id 解析
    /// （被选中的纪念日可能因伙伴切换后不在过滤集内，仍需能被 id 找回以渲染当前值）。
    private func allEntities() -> [AnniversaryEntity] {
        suggestedEntities(petID: nil)
    }

    /// 统一的候选展示标题：「宠物名 · 纪念日标题」。
    /// 始终携带宠物名，避免多宠物场景下「成为家人的日子」这类不含名字的标题不可区分。
    static func displayTitle(_ day: UpcomingDayProjection) -> String {
        String(localized: "widget.common.join \(day.petName) \(day.title)")
    }
}

// MARK: - 纪念日倒计时配置 Intent

/// 纪念日倒计时 Widget 的完整配置（伙伴 + 纪念日）。
///
/// 默认「自动（最近）」，与历史行为一致；用户可点名某个具体纪念日。当指定的纪念日
/// 在当前快照中已不存在时，由 `WidgetSelectionLogic.upcomingDay` 安全回退到最近。
struct SelectAnniversaryIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.intents.anniversary.settings.title"
    static var description = IntentDescription("widget.intents.anniversary.settings.description")

    // AppEntity 参数的 default: 只接受编译期字面量（构造调用被宏拒绝），
    // 默认值改由 PetEntityQuery.defaultResult() 提供（同一「全部伙伴」）。
    @Parameter(title: "widget.entity.pet")
    var pet: PetEntity

    // 同上：默认值由 AnniversaryEntityQuery.defaultResult() 提供（自动取最近）。
    @Parameter(title: "widget.entity.anniversary")
    var anniversary: AnniversaryEntity

    init() {}
    init(pet: PetEntity, anniversary: AnniversaryEntity) {
        self.pet = pet
        self.anniversary = anniversary
    }
}
