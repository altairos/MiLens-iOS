import XCTest
@testable import MiLens

/// PaywallViewModel 测试：产品加载（排序/默认选中/失败降级）、购买四分支、
/// 恢复购买三分支、权益流监听。全部经 MockStoreService，不触 StoreKit。
@MainActor
final class PaywallViewModelTests: XCTestCase {

    private func makeViewModel(
        purchaseBehavior: MockStoreService.PurchaseBehavior = .success,
        proStatus: ProStatus = .inactive
    ) -> (PaywallViewModel, MockStoreService) {
        let store = MockStoreService(proStatus: proStatus)
        store.purchaseBehavior = purchaseBehavior
        return (PaywallViewModel(store: store), store)
    }

    // MARK: - 加载

    func testLoadSuccessOrdersAndSelectsYearly() async {
        let (vm, store) = makeViewModel()
        await vm.load()
        XCTAssertEqual(vm.phase, .ready)
        XCTAssertEqual(store.loadCallCount, 1)
        XCTAssertEqual(vm.products.map(\.period), [.yearly, .monthly, .lifetime])
        XCTAssertEqual(vm.selectedID, MiLensProducts.yearly)
        XCTAssertEqual(vm.proStatus, .inactive)
    }

    func testLoadFailureEntersFailedPhase() async {
        let (vm, store) = makeViewModel()
        store.loadError = StoreServiceError.productNotFound("x")
        await vm.load()
        XCTAssertEqual(vm.phase, .failed)
        XCTAssertTrue(vm.products.isEmpty)
    }

    func testLoadKeepsExistingSelectionWhenStillAvailable() async {
        let (vm, _) = makeViewModel()
        await vm.load()
        vm.selectedID = MiLensProducts.monthly
        await vm.load()
        XCTAssertEqual(vm.selectedID, MiLensProducts.monthly)
    }

    // MARK: - 购买

    func testPurchaseSuccessMarksMessageAndActivatesPro() async {
        let (vm, store) = makeViewModel(purchaseBehavior: .success)
        await vm.load()
        await vm.purchaseSelected()
        XCTAssertEqual(store.purchaseCalls, [MiLensProducts.yearly])
        XCTAssertEqual(vm.purchaseMessage, .success)
        XCTAssertEqual(vm.proStatus, .active(productID: MiLensProducts.yearly))
        XCTAssertFalse(vm.isPurchasing)
    }

    func testPurchaseCancelledShowsNoMessage() async {
        let (vm, _) = makeViewModel(purchaseBehavior: .userCancelled)
        await vm.load()
        await vm.purchaseSelected()
        XCTAssertEqual(vm.purchaseMessage, .silent)
        XCTAssertEqual(vm.proStatus, .inactive)
    }

    func testPurchasePendingShowsPendingMessage() async {
        let (vm, _) = makeViewModel(purchaseBehavior: .pending)
        await vm.load()
        await vm.purchaseSelected()
        XCTAssertEqual(vm.purchaseMessage, .pending)
    }

    func testPurchaseFailureShowsFailedMessage() async {
        let (vm, _) = makeViewModel(purchaseBehavior: .failure)
        await vm.load()
        await vm.purchaseSelected()
        XCTAssertEqual(vm.purchaseMessage, .failed)
        XCTAssertEqual(vm.proStatus, .inactive)
    }

    func testPurchaseWithoutSelectionIsNoOp() async {
        let (vm, store) = makeViewModel()
        await vm.load()
        vm.selectedID = nil
        await vm.purchaseSelected()
        XCTAssertTrue(store.purchaseCalls.isEmpty)
        XCTAssertNil(vm.purchaseMessage)
    }

    // MARK: - 恢复购买

    func testRestoreWithActiveEntitlementReportsRestored() async {
        let (vm, store) = makeViewModel(proStatus: .active(productID: MiLensProducts.yearly))
        await vm.load()
        await vm.restore()
        XCTAssertEqual(store.restoreCallCount, 1)
        XCTAssertEqual(vm.restoreMessage, .restored)
    }

    func testRestoreWithoutEntitlementReportsNothing() async {
        let (vm, _) = makeViewModel(proStatus: .inactive)
        await vm.load()
        await vm.restore()
        XCTAssertEqual(vm.restoreMessage, .nothingToRestore)
    }

    func testRestoreErrorReportsFailed() async {
        let (vm, store) = makeViewModel()
        store.restoreError = StoreServiceError.verificationFailed
        await vm.load()
        await vm.restore()
        XCTAssertEqual(vm.restoreMessage, .failed)
    }

    // MARK: - 权益流监听

    func testOnAppearObservesStatusUpdates() async {
        let (vm, store) = makeViewModel()
        vm.onAppear()
        // 等待 load 完成
        for _ in 0..<100 where vm.phase != .ready {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        store.pushStatus(.active(productID: MiLensProducts.lifetime))
        for _ in 0..<100 where !vm.proStatus.isActive {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(vm.proStatus, .active(productID: MiLensProducts.lifetime))
    }

    // MARK: - 提示清理

    func testDismissMessagesClearsBoth() async {
        let (vm, _) = makeViewModel(purchaseBehavior: .failure)
        await vm.load()
        await vm.purchaseSelected()
        XCTAssertNotNil(vm.purchaseMessage)
        vm.dismissMessages()
        XCTAssertNil(vm.purchaseMessage)
        XCTAssertNil(vm.restoreMessage)
    }
}
