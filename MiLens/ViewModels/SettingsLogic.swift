//  SettingsLogic —— 「我的」页纯决策逻辑（无 IO / 无 SwiftUI 依赖，DESIGN.md §4）。
//
//  外观模式解析与持久化值、版本号文案、纪念提醒开关决策、字体许可数据、外链常量。
//  View 层只按返回的枚举/数据渲染；ColorScheme 映射留在 SwiftUI 层（MiLensApp）。

import Foundation

// MARK: - 外观模式

/// 外观模式（@AppStorage("appearanceMode") 持久化 rawValue）。
enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// 解析持久化值；未知值回退「跟随系统」（安全默认值）。
    static func parse(_ rawValue: String) -> AppearanceMode {
        AppearanceMode(rawValue: rawValue) ?? .system
    }
}

// MARK: - 照片副本系统备份策略（任务 3）

/// 照片副本是否参与系统 iCloud/iTunes 备份（DESIGN.md §7 媒体备份策略）。
/// - cloudOptimized：导入副本排除系统备份（默认，节省云空间——原图在系统相册可重建）
/// - dataSafe：导入副本纳入系统备份（数据安全优先——防止系统相册已清/换 Apple ID 时丢失）
/// 编辑成品（Edits/）始终允许备份，不受此设置影响。
enum PhotoBackupMode: String, CaseIterable, Sendable {
    case cloudOptimized
    case dataSafe

    /// 解析持久化值；未知值回退 cloudOptimized（安全默认值）。
    static func parse(_ rawValue: String) -> PhotoBackupMode {
        PhotoBackupMode(rawValue: rawValue) ?? .cloudOptimized
    }
}

// MARK: - 纪念提醒开关决策

enum ReminderToggleDecision: Equatable {
    /// 打开且已授权 → 幂等全量重调度
    case schedule
    /// 关闭 → 撤销全部已调度通知
    case cancelAll
    /// 打开但未授权 → 回弹开关 + 提示去系统设置
    case rollbackAndPrompt
}

// MARK: - 关于页字体许可数据

/// 字体来源与许可条目（UI-DESIGN.md §2.1 合规要求：关于页注明字体来源与 OFL 许可）。
struct FontCredit: Equatable, Sendable {
    /// 字体名（如「霞鹜文楷 LXGW WenKai」）
    let name: String
    /// 作者/出处说明（如「LXGW（基于 Fontworks Klee）」）
    let author: String
    /// 许可证名（SIL Open Font License 1.1）
    let licenseName: String
    /// 来源链接
    let sourceURL: String
}

enum SettingsLogic {

    // MARK: 外观

    static func appearanceMode(forRawValue rawValue: String) -> AppearanceMode {
        AppearanceMode.parse(rawValue)
    }

    // MARK: 版本号

    /// 关于页版本文案的原始组成部分；nil 回退 "-"（不伪装版本）。
    static func versionParts(marketing: String?, build: String?) -> (marketing: String, build: String) {
        (marketing ?? "-", build ?? "-")
    }

    // MARK: 纪念提醒开关

    /// 纪念提醒开关决策（对应源端设置开关语义：授权放开关路径，拒绝回弹）。
    static func resolveReminderToggle(enabled: Bool, authorized: Bool) -> ReminderToggleDecision {
        guard enabled else { return .cancelAll }
        return authorized ? .schedule : .rollbackAndPrompt
    }

    // MARK: 照片副本备份策略

    /// 根据备份模式决定导入副本是否排除系统备份。
    /// cloudOptimized → true（排除，节省云空间）；dataSafe → false（纳入，数据安全优先）。
    static func shouldExcludePhotos(_ mode: PhotoBackupMode) -> Bool {
        mode == .cloudOptimized
    }

    // MARK: 字体许可（Resources/Fonts/README.md 为事实来源）

    static let fontCredits: [FontCredit] = [
        FontCredit(
            name: "霞鹜文楷 LXGW WenKai",
            author: "LXGW（基于 Fontworks Klee）",
            licenseName: "SIL Open Font License 1.1",
            sourceURL: "https://github.com/lxgw/LxgwWenKai"
        ),
        FontCredit(
            name: "霞鶩文楷 TC LXGW WenKai TC",
            author: "LXGW（繁體版，基於 Fontworks Klee）",
            licenseName: "SIL Open Font License 1.1",
            sourceURL: "https://github.com/lxgw/LxgwWenKaiTC"
        ),
        FontCredit(
            name: "芫茜雅楷 JyunsaiKaai",
            author: "ItMarki（基於 Klee One、芫荽與霞鶩文楷）",
            licenseName: "SIL Open Font License 1.1",
            sourceURL: "https://github.com/ItMarki/jyunsaikaai"
        ),
        FontCredit(
            name: "Klee One",
            author: "Fontworks",
            licenseName: "SIL Open Font License 1.1",
            sourceURL: "https://github.com/fontworks-fonts/Klee"
        ),
        FontCredit(
            name: "Fraunces",
            author: "Undercase Type",
            licenseName: "SIL Open Font License 1.1",
            sourceURL: "https://github.com/undercasetype/Fraunces"
        ),
        FontCredit(
            name: "Jacques Francois",
            author: "Cyreal",
            licenseName: "SIL Open Font License 1.1",
            sourceURL: "https://github.com/google/fonts/tree/main/ofl/jacquesfrancois"
        )
    ]

    // MARK: 外链（单一事实来源）

    enum Links {
        /// 隐私政策（docs/AppStore-metadata.md §1：MiLens 托管地址）
        static let privacyPolicy = "https://miovelle.cn/milens/privacy-policy.html"
        /// 服务条款（MiLens 托管页面；购买仍受 Apple 相关条款约束）
        static let termsOfService = "https://miovelle.cn/milens/terms-of-service.html"
        /// App Store 订阅管理页（Pro 已解锁时「管理订阅」入口）
        static let manageSubscriptions = "https://apps.apple.com/account/subscriptions"
    }
}
