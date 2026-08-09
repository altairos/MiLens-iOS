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
    func testStreamPushStillUpdatesStatus() async {
        let store = MockStoreService(proStatus: .inactive)
        let entitlement = ProEntitlementStore(store: store)

        store.pushStatus(.active(productID: MiLensProducts.yearly))
        for _ in 0..<100 where !entitlement.isPro {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(entitlement.status, .active(productID: MiLensProducts.yearly))
    }

    // MARK: - 注册表生命周期竞态（评审阻塞项）

    private func waitRegistryCount(_ expected: Int, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while await ProEntitlementStore.registry.activeCount != expected {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }

    /// 正常路径：注册后取消 → 任务取消且注册表清空。
    func testCancelRemovesRegisteredTask() async {
        let store = MockStoreService(proStatus: .inactive)
        var entitlement: ProEntitlementStore? = ProEntitlementStore(store: store)
        let id = ObjectIdentifier(entitlement!)

        XCTAssertTrue(await waitRegistryCount(1), "注册任务应写入注册表")

        await ProEntitlementStore.registry.cancel(id)
        let count = await ProEntitlementStore.registry.activeCount
        XCTAssertEqual(count, 0, "取消后注册表不应残留任务")
        entitlement = nil
    }

    /// 乱序：cancel 先于 register 到达 actor → 晚到的注册被立即取消且不写入注册表
    /// （此前会把已结束的任务重新写入，形成残留——评审阻塞项）。
    func testCancelBeforeRegisterCancelsLateRegistration() async {
        let id = ObjectIdentifier(NSObject())
        let task = Task {}

        await ProEntitlementStore.registry.cancel(id)      // deinit 的清理先到达
        await ProEntitlementStore.registry.register(id, task)  // init 的注册后到达

        XCTAssertTrue(task.isCancelled, "晚到的注册必须被取消墓碑立即取消")
        let count = await ProEntitlementStore.registry.activeCount
        XCTAssertEqual(count, 0, "注册表不应残留已取消的任务")
    }

    /// 立即释放（deinit 触发清理）：无论 register/cancel 乱序如何，注册表最终清空。
    func testImmediateReleaseCleansRegistry() async {
        let store = MockStoreService(proStatus: .inactive)
        var entitlement: ProEntitlementStore? = ProEntitlementStore(store: store)
        _ = ObjectIdentifier(entitlement!)

        entitlement = nil  // 触发 deinit → 异步 cancel

        XCTAssertTrue(await waitRegistryCount(0, timeout: 2),
                      "立即释放后注册表应清空（无保活环、无残留）")
    }

    /// 流立即结束：监听任务退出时清理注册表，不残留条目。
    func testStreamImmediateEndCleansRegistry() async {
        let store = MockStoreService(proStatus: .inactive)
        store.finishUpdates()  // 流立即结束（for await 立即返回）
        let entitlement = ProEntitlementStore(store: store)
        _ = entitlement

        XCTAssertTrue(await waitRegistryCount(0, timeout: 2),
                      "流结束后注册表应清空")
    }
}
