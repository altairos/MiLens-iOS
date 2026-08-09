//  ProEntitlementStoreTests —— 应用级权益 store 的启动校准与流订阅语义。
//
//  背景：权益初始 .inactive，Transaction.updates 不保证冷启动推送当前权益；
//  若 RootTabView 首次出现不 refresh()，已购用户首次进入「创作」时 isPro 仍为 false，
//  拼豆入口会被误导向付费墙。本测试锁定「启动 refresh 恢复真实权益」的行为规格。

import XCTest
@testable import MiLens

@MainActor
final class ProEntitlementStoreTests: XCTestCase {

    /// 缺陷前提：已购用户创建 store 后、任何 refresh 前，状态仍是初始 .inactive
    /// （AsyncStream 无推送时 for await 挂起，冷启动不会自动校准）。
    func testInitialStatusInactiveBeforeLaunchRefresh() async {
        let store = MockStoreService(proStatus: .active(productID: MiLensProducts.lifetime))
        let entitlement = ProEntitlementStore(store: store)

        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(entitlement.status, .inactive)
        XCTAssertFalse(entitlement.isPro)
    }

    /// 修复目标：已购用户启动后 RootTabView 首次 refresh()，权益恢复 active，
    /// 创作门控与拼豆路由不再误判到付费墙。
    func testLaunchRefreshRecoversActiveEntitlement() async {
        let store = MockStoreService(proStatus: .active(productID: MiLensProducts.lifetime))
        let entitlement = ProEntitlementStore(store: store)
        XCTAssertEqual(entitlement.status, .inactive)

        await entitlement.refresh()

        XCTAssertEqual(entitlement.status, .active(productID: MiLensProducts.lifetime))
        XCTAssertTrue(entitlement.isPro)
    }

    /// 未购买用户 refresh 后保持 inactive（启动校准不引入误判）。
    func testLaunchRefreshKeepsInactiveWhenNoEntitlement() async {
        let store = MockStoreService(proStatus: .inactive)
        let entitlement = ProEntitlementStore(store: store)

        await entitlement.refresh()

        XCTAssertEqual(entitlement.status, .inactive)
        XCTAssertFalse(entitlement.isPro)
    }

    /// 流推送仍生效（购买/恢复/Transaction.updates 路径不受启动 refresh 影响）。
    ///
    /// 注入独立 ListenerRegistry（不复用 .shared）：串行/并行测试间注册表状态隔离，
    /// 避免宿主 App 与并行测试类的计数相互干扰。deadline 轮询给并行负载下
    /// 充足的调度预算。
    func testStreamPushStillUpdatesStatus() async {
        let registry = ProEntitlementStore.ListenerRegistry()
        let store = MockStoreService(proStatus: .inactive)
        let entitlement = ProEntitlementStore(store: store, registry: registry)

        store.pushStatus(.active(productID: MiLensProducts.yearly))
        let deadline = Date().addingTimeInterval(2)
        while !entitlement.isPro, Date() <= deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(entitlement.status, .active(productID: MiLensProducts.yearly))
    }

    // MARK: - 注册表生命周期竞态（评审阻塞项）

    /// 等待注册表计数达到期望值（注入独立注册表，不受宿主 App/并行测试类干扰）。
    private func waitRegistryCount(
        _ expected: Int, timeout: TimeInterval = 2,
        registry: ProEntitlementStore.ListenerRegistry
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while await registry.activeCount != expected {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }

    /// 正常路径：注册后取消 → 任务取消且注册表清空，不残留墓碑。
    func testCancelRemovesRegisteredTask() async {
        let registry = ProEntitlementStore.ListenerRegistry()
        let id = UUID()
        let task = Task {}
        await registry.register(id, task)

        let count1 = await registry.activeCount
        XCTAssertEqual(count1, 1, "注册任务应写入注册表")

        await registry.cancel(id)
        let count2 = await registry.activeCount
        XCTAssertEqual(count2, 0, "取消后注册表不应残留任务")
    }

    /// 正常取消（cancel 在 register 之后）不创建墓碑——后续相同令牌的注册不被误杀。
    /// 这是 UUID 令牌 + 条件墓碑的核心保证：cancel 找到任务时直接取消，
    /// 只有 cancel 先于 register 的竞态才创建一次性墓碑。
    func testCancelAfterRegisterLeavesNoTombstone() async {
        let registry = ProEntitlementStore.ListenerRegistry()
        let id = UUID()
        let task1 = Task {}
        await registry.register(id, task1)
        await registry.cancel(id)

        // 取消后用相同令牌重新注册不应被墓碑误杀
        let task2 = Task {}
        await registry.register(id, task2)
        XCTAssertFalse(task2.isCancelled, "正常取消后的重新注册不应被墓碑误杀")
        let count = await registry.activeCount
        XCTAssertEqual(count, 1)
    }

    /// 乱序：cancel 先于 register 到达 actor → 晚到的注册被立即取消且不写入注册表
    /// （此前会把已结束的任务重新写入，形成残留——评审阻塞项）。
    func testCancelBeforeRegisterCancelsLateRegistration() async {
        let registry = ProEntitlementStore.ListenerRegistry()
        let id = UUID()
        let task = Task {}

        await registry.cancel(id)      // deinit 的清理先到达
        await registry.register(id, task)  // init 的注册后到达

        XCTAssertTrue(task.isCancelled, "晚到的注册必须被取消墓碑立即取消")
        let count = await registry.activeCount
        XCTAssertEqual(count, 0, "注册表不应残留已取消的任务")
    }

    /// 立即释放（deinit 触发清理）：无论 register/cancel 乱序如何，注册表最终清空。
    func testImmediateReleaseCleansRegistry() async {
        let registry = ProEntitlementStore.ListenerRegistry()
        let store = MockStoreService(proStatus: .inactive)
        var entitlement: ProEntitlementStore? = ProEntitlementStore(store: store, registry: registry)

        entitlement = nil  // 触发 deinit → 异步 cancel

        let cleared = await waitRegistryCount(0, registry: registry)
        XCTAssertTrue(cleared,
                      "立即释放后注册表应清空（无保活环、无残留）")
    }

    /// 流立即结束：监听任务退出时清理注册表，不残留条目。
    func testStreamImmediateEndCleansRegistry() async {
        let registry = ProEntitlementStore.ListenerRegistry()
        let store = MockStoreService(proStatus: .inactive)
        store.finishUpdates()  // 流立即结束（for await 立即返回）
        let entitlement = ProEntitlementStore(store: store, registry: registry)
        _ = entitlement

        let cleared = await waitRegistryCount(0, registry: registry)
        XCTAssertTrue(cleared,
                      "流结束后注册表应清空")
    }
}
