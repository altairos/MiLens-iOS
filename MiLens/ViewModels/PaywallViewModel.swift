//  PaywallViewModel —— 付费墙编排层（@Observable）。
//
//  只依赖 StoreService 窄协议与 PaywallLogic 纯决策，不直接引用 StoreKit；
//  测试注入 MockStoreService 即可单测（产品加载/选中/购买/恢复/权益监听）。

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
    private(set) var proStatus: ProStatus = .inactive
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    /// 购买/恢复结果提示（View 按枚举取本地化文案展示 alert）
    private(set) var purchaseMessage: PaywallLogic.PurchaseMessage?
    private(set) var restoreMessage: PaywallLogic.RestoreMessage?

    private let store: any StoreService
    /// deinit 为 nonisolated 上下文，Task 放入非隔离容器以便释放时取消（SE-0371 前标准做法）
    private final class ListenerBox {
        var task: Task<Void, Never>?
    }
    private let listenerBox = ListenerBox()

    init(store: any StoreService) {
        self.store = store
    }

    deinit {
        listenerBox.task?.cancel()
    }

    var selectedProduct: StoreProductInfo? {
        products.first { $0.id == selectedID }
    }

    // MARK: - 生命周期

    /// 进入付费墙：开始监听权益变更并加载产品。
    func onAppear() {
        guard listenerBox.task == nil else { return }
        listenerBox.task = Task { [weak self] in
            guard let self else { return }
            for await status in store.proStatusUpdates {
                guard !Task.isCancelled else { return }
                self.proStatus = status
            }
        }
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
            proStatus = await store.currentProStatus()
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
                proStatus = await store.currentProStatus()
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
            proStatus = await store.currentProStatus()
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
