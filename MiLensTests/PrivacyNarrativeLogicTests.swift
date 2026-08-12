//  PrivacyNarrativeLogicTests —— 隐私叙事差异化纯逻辑测试
//
//  验证 MarketProfile.privacyNarrativeStrength → 隐私承诺项列表的映射：
//  标准市场 3 条，GDPR 区追加第 4 条强化声明。

import XCTest
@testable import MiLens

final class PrivacyNarrativeLogicTests: XCTestCase {

    // MARK: - 标准市场（3 条）

    func testStandardMarketReturnsThreeItems() {
        let profile = MarketProfile(market: .china, usesWenKaiDisplay: true,
                                    privacyNarrativeStrength: .standard)
        let kinds = PrivacyNarrativeLogic.commitmentKinds(for: profile)
        XCTAssertEqual(kinds.count, 3)
        XCTAssertEqual(kinds, [.ondevice, .local, .control])
    }

    func testEnglishMarketStandard() {
        let profile = MarketProfile(market: .english, usesWenKaiDisplay: false,
                                    privacyNarrativeStrength: .standard)
        let kinds = PrivacyNarrativeLogic.commitmentKinds(for: profile)
        XCTAssertEqual(kinds.count, 3)
    }

    func testJapanStandard() {
        let profile = MarketProfile(market: .japan, usesWenKaiDisplay: false,
                                    privacyNarrativeStrength: .standard)
        let kinds = PrivacyNarrativeLogic.commitmentKinds(for: profile)
        XCTAssertEqual(kinds.count, 3)
        XCTAssertFalse(kinds.contains(.gdpr))
    }

    // MARK: - GDPR 区（4 条，含强化声明）

    func testGermanyStrongReturnsFourItems() {
        let profile = MarketProfile(market: .germany, usesWenKaiDisplay: false,
                                    privacyNarrativeStrength: .strong)
        let kinds = PrivacyNarrativeLogic.commitmentKinds(for: profile)
        XCTAssertEqual(kinds.count, 4)
        XCTAssertEqual(kinds.last, .gdpr, "GDPR 区应追加强化声明")
    }

    func testFranceStrongReturnsFourItems() {
        let profile = MarketProfile(market: .france, usesWenKaiDisplay: false,
                                    privacyNarrativeStrength: .strong)
        let kinds = PrivacyNarrativeLogic.commitmentKinds(for: profile)
        XCTAssertEqual(kinds.count, 4)
        XCTAssertEqual(kinds[3], .gdpr)
    }

    // MARK: - 顺序不变量

    func testStrongMarketOrderPreserved() {
        let profile = MarketProfile(market: .germany, usesWenKaiDisplay: false,
                                    privacyNarrativeStrength: .strong)
        let kinds = PrivacyNarrativeLogic.commitmentKinds(for: profile)
        // 强化声明始终在最后，不破坏前三条顺序
        XCTAssertEqual(kinds, [.ondevice, .local, .control, .gdpr])
    }

    func testStandardMarketNeverContainsGdpr() {
        let standardMarkets: [MarketProfile.Market] = [.china, .taiwan, .japan, .korea, .english, .other]
        for market in standardMarkets {
            let profile = MarketProfile(market: market, usesWenKaiDisplay: false,
                                        privacyNarrativeStrength: .standard)
            let kinds = PrivacyNarrativeLogic.commitmentKinds(for: profile)
            XCTAssertFalse(kinds.contains(.gdpr), "\(market) 不应含 GDPR 强化声明")
        }
    }

    // MARK: - icon 映射

    func testAllKindsHaveDistinctIcons() {
        let icons = PrivacyCommitKind.allCases.map(\.icon)
        XCTAssertEqual(Set(icons).count, icons.count, "每条承诺的图标应唯一")
    }
}
