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
}
