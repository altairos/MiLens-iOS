//  StoreService —— 订阅/购买窄协议（DESIGN.md §9 平台隔离、§2 StoreKit 2）。
//
//  真实实现（StoreKit2StoreService）与 mock 分离：ViewModel 只依赖本协议与
//  StoreProductInfo 投影，不直接引用 StoreKit.Product。
//
//  P0-4 付费墙纪律（docs/UI_REWORK_AUDIT.md）：价格、试用天数、促销信息必须全部
//  来自 StoreKit Product（经投影传入 UI），生产代码不硬编码任何金额/试用天数。
//  产品 ID 为编译期常量，与 MiLens/Resources/Products.storekit（本地 StoreKit
//  Testing）和 App Store Connect 录入保持一致（docs/AppStore-metadata.md §7）。

import Foundation

/// MiLens Pro 产品 ID 常量。
enum MiLensProducts {
    static let monthly = "com.milens.pro.monthly"
    static let yearly = "com.milens.pro.yearly"
    static let lifetime = "com.milens.pro.lifetime"
    static let allIDs = [monthly, yearly, lifetime]
}

/// 产品计费周期（仅用于展示排序、视觉突出与条款文案决策，不承载价格）。
enum StoreProductPeriod: String, Equatable, Sendable {
    case monthly
    case yearly
    /// 永久买断（非消耗品）
    case lifetime
    case other
}

/// 面向 UI 的产品投影。价格与试用文案全部来自 StoreKit Product（已本地化）。
struct StoreProductInfo: Equatable, Sendable, Identifiable {
    let id: String
    /// 本地化显示名（Product.displayName）
    let displayName: String
    /// 本地化描述（Product.description）
    let descriptionText: String
    /// 本地化价格（Product.displayPrice，含货币符号）——UI 唯一价格来源
    let displayPrice: String
    let period: StoreProductPeriod
    /// 免费试用天数（存在免费 introductoryOffer 且当前用户有资格时）；否则为 nil
    let trialDays: Int?
}

/// 购买结果（Product.PurchaseResult 的投影）。用户取消不视为错误。
enum StorePurchaseOutcome: Equatable, Sendable {
    case success
    case userCancelled
    case pending
}

/// Pro 权益状态（Transaction.currentEntitlements 的投影）。
enum ProStatus: Equatable, Sendable {
    case inactive
    case active(productID: String)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

enum StoreServiceError: Error, Equatable {
    /// 交易验证失败（签名/来源不可信）
    case verificationFailed
    /// 请求的产品不在已加载列表中
    case productNotFound(String)
}

/// 订阅服务窄协议。组合根注入真实实现；测试与预览注入 MockStoreService。
protocol StoreService {
    /// 拉取产品（含本地化价格与试用信息）。失败抛错，UI 进入可重试降级态。
    func loadProducts() async throws -> [StoreProductInfo]
    /// 购买指定产品。用户取消返回 .userCancelled（不抛错）。
    func purchase(productID: String) async throws -> StorePurchaseOutcome
    /// 恢复购买（AppStore.sync 后刷新权益）。
    func restorePurchases() async throws
    /// 当前 Pro 权益状态。
    func currentProStatus() async -> ProStatus
    /// 权益变更流（Transaction.updates 驱动；购买/恢复成功后也会推送）。
    var proStatusUpdates: AsyncStream<ProStatus> { get }
}
