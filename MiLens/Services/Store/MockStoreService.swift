//  MockStoreService —— StoreService 的测试/预览实现。
//
//  可配置产品、购买/恢复行为与权益状态；记录调用供断言。
//  注意：sampleProducts 中的金额字符串是**测试夹具**（镜像 Products.storekit 本地
//  配置），只出现在 mock 与测试中；生产 UI 价格永远来自 StoreKit Product（P0-4）。

import Foundation

final class MockStoreService: StoreService {

    enum PurchaseBehavior: Sendable {
        case success
        case userCancelled
        case pending
        case failure
    }

    var products: [StoreProductInfo]
    var proStatus: ProStatus
    var purchaseBehavior: PurchaseBehavior = .success
    var loadError: Error?
    var restoreError: Error?

    private(set) var loadCallCount = 0
    private(set) var purchaseCalls: [String] = []
    private(set) var restoreCallCount = 0

    private let statusContinuation: AsyncStream<ProStatus>.Continuation
    private let statusStream: AsyncStream<ProStatus>

    init(
        products: [StoreProductInfo] = MockStoreService.sampleProducts,
        proStatus: ProStatus = .inactive
    ) {
        self.products = products
        self.proStatus = proStatus
        (statusStream, statusContinuation) = AsyncStream.makeStream(of: ProStatus.self)
    }

    var proStatusUpdates: AsyncStream<ProStatus> { statusStream }

    /// 测试直接推送权益变更（模拟 Transaction.updates）。
    func pushStatus(_ status: ProStatus) {
        proStatus = status
        statusContinuation.yield(status)
    }

    func loadProducts() async throws -> [StoreProductInfo] {
        loadCallCount += 1
        if let loadError { throw loadError }
        return products
    }

    func purchase(productID: String) async throws -> StorePurchaseOutcome {
        purchaseCalls.append(productID)
        switch purchaseBehavior {
        case .success:
            pushStatus(.active(productID: productID))
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        case .failure:
            throw StoreServiceError.verificationFailed
        }
    }

    func restorePurchases() async throws {
        restoreCallCount += 1
        if let restoreError { throw restoreError }
        statusContinuation.yield(proStatus)
    }

    func currentProStatus() async -> ProStatus {
        proStatus
    }
}

extension MockStoreService {
    /// 镜像 Products.storekit 的本地测试产品（仅测试/预览使用）。
    static let sampleProducts: [StoreProductInfo] = [
        StoreProductInfo(
            id: MiLensProducts.monthly,
            displayName: "MiLens Pro 月度订阅",
            descriptionText: "每月自动续费。免费试用 7 天，试用期内可随时取消。",
            displayPrice: "¥18.00",
            period: .monthly,
            trialDays: 7
        ),
        StoreProductInfo(
            id: MiLensProducts.yearly,
            displayName: "MiLens Pro 年度订阅",
            descriptionText: "每年自动续费。免费试用 7 天。",
            displayPrice: "¥98.00",
            period: .yearly,
            trialDays: 7
        ),
        StoreProductInfo(
            id: MiLensProducts.lifetime,
            displayName: "MiLens Pro 永久版",
            descriptionText: "一次购买，永久解锁 20 个宠物档案、不限拼豆生成与完整成长历史，无后续费用。",
            displayPrice: "¥298.00",
            period: .lifetime,
            trialDays: nil
        )
    ]
}
