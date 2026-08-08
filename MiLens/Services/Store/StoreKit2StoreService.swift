//  StoreKit2StoreService —— StoreService 的 StoreKit 2 真实实现。
//
//  接线要点（UI Rework 4.5 / PLAN.md P5）：
//  - Product.products(for:) 拉取产品，投影为 StoreProductInfo
//    （价格 displayPrice / 试用 introductoryOffer 全部来自 Product，不硬编码）。
//  - purchase() 发起购买；验证通过（VerificationResult.verified）后 finish。
//  - Transaction.updates 常驻监听（App 内其他路径/家庭共享/App Store 侧变更），
//    验证通过 → finish → 推送权益状态。
//  - 恢复购买走 AppStore.sync()，随后刷新 Transaction.currentEntitlements。
//  - 本地验证：Products.storekit + scheme 关联（StoreKit Testing），
//    沙盒验证留真机/上架前（DEVELOPMENT.md §4.4）。

import Foundation
import StoreKit

/// 非隔离 + @unchecked Sendable：可变状态 productsByID 只在调用方（MainActor ViewModel）
/// 串行访问；Transaction.updates 监听任务只触碰线程安全的 AsyncStream.Continuation，
/// 不读写 productsByID。避免 MainActor 隔离见证非隔离协议的跨隔离告警（Swift 6 为错误）。
final class StoreKit2StoreService: StoreService, @unchecked Sendable {

    /// 已加载产品缓存（purchase 需要 Product 实例）
    private var productsByID: [String: Product] = [:]

    private let statusContinuation: AsyncStream<ProStatus>.Continuation
    private let statusStream: AsyncStream<ProStatus>
    private var updatesTask: Task<Void, Never>?

    init() {
        (statusStream, statusContinuation) = AsyncStream.makeStream(of: ProStatus.self)
        listenForTransactions()
    }

    deinit {
        updatesTask?.cancel()
    }

    var proStatusUpdates: AsyncStream<ProStatus> { statusStream }

    // MARK: - 产品

    func loadProducts() async throws -> [StoreProductInfo] {
        let products = try await Product.products(for: MiLensProducts.allIDs)
        var infos: [StoreProductInfo] = []
        for product in products {
            productsByID[product.id] = product
            infos.append(await Self.makeInfo(for: product))
        }
        return infos
    }

    /// Product → StoreProductInfo 投影。试用信息只在「免费 introductoryOffer
    /// 且当前用户有资格」时给出天数，避免向不符合资格的用户承诺试用。
    private static func makeInfo(for product: Product) async -> StoreProductInfo {
        var period: StoreProductPeriod = .lifetime
        var trialDays: Int?
        if let subscription = product.subscription {
            period = mapPeriod(subscription.subscriptionPeriod)
            if let intro = subscription.introductoryOffer,
               intro.paymentMode == .freeTrial,
               (try? await subscription.isEligibleForIntroOffer) == true {
                trialDays = days(of: intro.period)
            }
        }
        return StoreProductInfo(
            id: product.id,
            displayName: product.displayName,
            descriptionText: product.description,
            displayPrice: product.displayPrice,
            period: period,
            trialDays: trialDays
        )
    }

    private static func mapPeriod(_ period: Product.SubscriptionPeriod) -> StoreProductPeriod {
        switch (period.unit, period.value) {
        case (.month, 1): return .monthly
        case (.year, 1): return .yearly
        default: return .other
        }
    }

    /// 订阅周期折算天数（用于试用文案）。月/年按 30/365 近似，仅 introductoryOffer 使用。
    private static func days(of period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return period.value
        }
    }

    // MARK: - 购买

    func purchase(productID: String) async throws -> StorePurchaseOutcome {
        let product = try await product(for: productID)
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            await transaction.finish()
            await pushCurrentStatus()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    private func product(for productID: String) async throws -> Product {
        if let cached = productsByID[productID] { return cached }
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw StoreServiceError.productNotFound(productID)
        }
        productsByID[productID] = product
        return product
    }

    // MARK: - 恢复购买

    func restorePurchases() async throws {
        try await AppStore.sync()
        await pushCurrentStatus()
    }

    // MARK: - 权益

    func currentProStatus() async -> ProStatus {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            guard MiLensProducts.allIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration <= Date() { continue }
            return .active(productID: transaction.productID)
        }
        return .inactive
    }

    private func pushCurrentStatus() async {
        statusContinuation.yield(await currentProStatus())
    }

    // MARK: - Transaction.updates 监听

    /// 常驻监听交易更新（含 App Store 侧购买/续期/家庭共享变更）。
    /// 验证通过 → finish → 推送最新权益；验证失败不 finish（保留待处理）。
    private func listenForTransactions() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? Self.checkVerified(result) else { continue }
                await transaction.finish()
                await self.pushCurrentStatus()
            }
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreServiceError.verificationFailed
        case .verified(let value): return value
        }
    }
}
