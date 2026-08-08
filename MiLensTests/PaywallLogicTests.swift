import XCTest
@testable import MiLens

/// PaywallLogic 测试：展示排序（年度优先）、默认选中、CTA/条款形态、
/// 购买与恢复结果 → 用户提示映射。
final class PaywallLogicTests: XCTestCase {

    private func product(
        _ id: String,
        period: StoreProductPeriod,
        trialDays: Int? = nil
    ) -> StoreProductInfo {
        StoreProductInfo(
            id: id,
            displayName: id,
            descriptionText: "",
            displayPrice: "¥0.00",
            period: period,
            trialDays: trialDays
        )
    }

    // MARK: - 排序与选中

    func testOrderedForDisplayPutsYearlyFirst() {
        let products = [
            product("lifetime", period: .lifetime),
            product("monthly", period: .monthly),
            product("yearly", period: .yearly)
        ]
        XCTAssertEqual(
            PaywallLogic.orderedForDisplay(products).map(\.id),
            ["yearly", "monthly", "lifetime"]
        )
    }

    func testDefaultSelectionPrefersYearly() {
        let products = [
            product("monthly", period: .monthly),
            product("yearly", period: .yearly)
        ]
        XCTAssertEqual(PaywallLogic.defaultSelectionID(products), "yearly")
    }

    func testDefaultSelectionFallsBackToFirst() {
        let products = [product("monthly", period: .monthly)]
        XCTAssertEqual(PaywallLogic.defaultSelectionID(products), "monthly")
        XCTAssertNil(PaywallLogic.defaultSelectionID([]))
    }

    func testIsFeaturedOnlyForYearly() {
        XCTAssertTrue(PaywallLogic.isFeatured(product("y", period: .yearly)))
        XCTAssertFalse(PaywallLogic.isFeatured(product("m", period: .monthly)))
        XCTAssertFalse(PaywallLogic.isFeatured(product("l", period: .lifetime)))
    }

    // MARK: - CTA 形态

    func testCTATrialWhenSubscriptionHasTrialDays() {
        XCTAssertEqual(
            PaywallLogic.ctaKind(for: product("y", period: .yearly, trialDays: 7)),
            .trial(days: 7)
        )
    }

    func testCTASubscribeWhenNoTrial() {
        XCTAssertEqual(
            PaywallLogic.ctaKind(for: product("m", period: .monthly)),
            .subscribe
        )
    }

    func testCTALifetimeIgnoresTrialDays() {
        XCTAssertEqual(
            PaywallLogic.ctaKind(for: product("l", period: .lifetime, trialDays: 7)),
            .lifetime
        )
    }

    func testCTAUnavailableWhenNoSelection() {
        XCTAssertEqual(PaywallLogic.ctaKind(for: nil), .unavailable)
    }

    // MARK: - 条款形态

    func testTermsKindTrialSubscription() {
        XCTAssertEqual(
            PaywallLogic.termsKind(for: product("m", period: .monthly, trialDays: 7)),
            .trialSubscription
        )
    }

    func testTermsKindPlainSubscription() {
        XCTAssertEqual(
            PaywallLogic.termsKind(for: product("m", period: .monthly)),
            .plainSubscription
        )
    }

    func testTermsKindLifetime() {
        XCTAssertEqual(
            PaywallLogic.termsKind(for: product("l", period: .lifetime)),
            .lifetime
        )
    }

    // MARK: - 结果提示

    func testPurchaseOutcomeMessages() {
        XCTAssertEqual(PaywallLogic.message(for: .success), .success)
        XCTAssertEqual(PaywallLogic.message(for: .userCancelled), .silent)
        XCTAssertEqual(PaywallLogic.message(for: .pending), .pending)
    }

    func testRestoreMessages() {
        XCTAssertEqual(
            PaywallLogic.message(restoredTo: .active(productID: "x")),
            .restored
        )
        XCTAssertEqual(PaywallLogic.message(restoredTo: .inactive), .nothingToRestore)
    }
}
