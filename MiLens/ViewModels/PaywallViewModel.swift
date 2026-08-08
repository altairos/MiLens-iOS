//  PaywallViewModel —— 付费墙编排层（@Observable）。
//
//  只依赖 StoreService 窄协议与 PaywallLogic 纯决策，不直接引用 StoreKit；
//  测试注入 MockStoreService 即可单测（产品加载/选中/购买/恢复/权益监听）。
//  权益状态读应用级 ProEntitlementStore（proStatusUpdates 唯一流消费者，P2 广播语义收口），
//  不再直接消费 store.proStatusUpdates，避免多页面并发消费竞争元素。

import Foundation
import Observation

@MainActor
@Observable
final class PaywallViewModel {

    enum Phase: Equatable {
        case loading
        case ready
        /// 产品加载失败（降级态，可重试）
        case failed
    }

    private(set) var phase: Phase = .loading
    /// 已按 PaywallLogic.orderedForDisplay 排序（年度优先）
    private(set) var products: [StoreProductInfo] = []
    var selectedID: String?
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    /// 购买/恢复结果提示（View 按枚举取本地化文案展示 alert）
    private(set) var purchaseMessage: PaywallLogic.PurchaseMessage?
    private(set) var restoreMessage: PaywallLogic.RestoreMessage?

    private let store: any StoreService
    private let entitlement: ProEntitlementStore

    /// 当前权益（读应用级权益 store——权益状态的单一事实源）。
    var proStatus: ProStatus { entitlement.status }

    init(store: any StoreService, entitlement: ProEntitlementStore) {
        self.store = store
        self.entitlement = entitlement
    }

    var selectedProduct: StoreProductInfo? {
        products.first { $0.id == selectedID }
    }

    // MARK: - 生命周期

    /// 进入付费墙：加载产品并校准一次权益（权益流由应用级 store 常驻消费）。
    func onAppear() {
        Task { await load() }
    }

    // MARK: - 产品加载

    func load() async {
        phase = .loading
        do {
            let loaded = try await store.loadProducts()
            products = PaywallLogic.orderedForDisplay(loaded)
            if selectedID == nil || !products.contains(where: { $0.id == selectedID }) {
                selectedID = PaywallLogic.defaultSelectionID(loaded)
            }
            await entitlement.refresh()
            phase = .ready
        } catch {
            products = []
            phase = .failed
        }
    }

    // MARK: - 购买

    func purchaseSelected() async {
        guard !isPurchasing, let productID = selectedID else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let outcome = try await store.purchase(productID: productID)
            purchaseMessage = PaywallLogic.message(for: outcome)
            if outcome == .success {
                await entitlement.refresh()
            }
        } catch {
            purchaseMessage = .failed
        }
    }

    // MARK: - 恢复购买

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await store.restorePurchases()
            await entitlement.refresh()
            restoreMessage = PaywallLogic.message(restoredTo: proStatus)
        } catch {
            restoreMessage = .failed
        }
    }

    // MARK: - 提示清理

    func dismissMessages() {
        purchaseMessage = nil
        restoreMessage = nil
    }
}
