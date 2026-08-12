//  MarketProfileTests —— 区域差异化配置解析纯逻辑测试
//
//  验证 Locale → MarketProfile 映射的正确性，重点守护：
//  1. 市场按地区聚合（德语区 DE/AT/CH → .germany，英语区多国 → .english）
//  2. usesWenKai 仅 zh-Hans 为 true（zh-Hant/ja/ko 必须回退系统字体，否则缺字）
//  3. privacy strong 仅 GDPR 区（germany/france）
//  4. 字体差异（语言层）与市场差异（地区层）相互独立

import XCTest
@testable import MiLens

final class MarketProfileTests: XCTestCase {

    // MARK: - 首发语言 × 默认地区的解析

    func testChinaSimplifiedChinese() {
        let p = MarketProfile.resolve(from: Locale(identifier: "zh-Hans_CN"))
        XCTAssertEqual(p.market, .china)
        XCTAssertTrue(p.usesWenKaiDisplay, "简中应使用霞鹜文楷")
        XCTAssertEqual(p.privacyNarrativeStrength, .standard)
    }

    func testTaiwanTraditionalChinese() {
        let p = MarketProfile.resolve(from: Locale(identifier: "zh-Hant_TW"))
        XCTAssertEqual(p.market, .taiwan)
        XCTAssertFalse(p.usesWenKaiDisplay, "繁中不能用文楷（缺字）")
        XCTAssertEqual(p.privacyNarrativeStrength, .standard)
    }

    func testJapan() {
        let p = MarketProfile.resolve(from: Locale(identifier: "ja_JP"))
        XCTAssertEqual(p.market, .japan)
        XCTAssertFalse(p.usesWenKaiDisplay)
        XCTAssertEqual(p.privacyNarrativeStrength, .standard)
    }

    func testKorea() {
        let p = MarketProfile.resolve(from: Locale(identifier: "ko_KR"))
        XCTAssertEqual(p.market, .korea)
        XCTAssertFalse(p.usesWenKaiDisplay)
        XCTAssertEqual(p.privacyNarrativeStrength, .standard)
    }

    func testEnglishUS() {
        let p = MarketProfile.resolve(from: Locale(identifier: "en_US"))
        XCTAssertEqual(p.market, .english)
        XCTAssertFalse(p.usesWenKaiDisplay)
        XCTAssertEqual(p.privacyNarrativeStrength, .standard)
    }

    // MARK: - GDPR 区隐私叙事强度

    func testGermanyPrivacyStrong() {
        let p = MarketProfile.resolve(from: Locale(identifier: "de_DE"))
        XCTAssertEqual(p.market, .germany)
        XCTAssertFalse(p.usesWenKaiDisplay)
        XCTAssertEqual(p.privacyNarrativeStrength, .strong, "德语区(GDPR 发源地)隐私叙事应为 strong")
    }

    func testFrancePrivacyStrong() {
        let p = MarketProfile.resolve(from: Locale(identifier: "fr_FR"))
        XCTAssertEqual(p.market, .france)
        XCTAssertFalse(p.usesWenKaiDisplay)
        XCTAssertEqual(p.privacyNarrativeStrength, .strong, "法语区(GDPR)隐私叙事应为 strong")
    }

    // MARK: - 德语区地区聚合（DE/AT/CH → .germany）

    func testAustriaAggregatesToGermanyMarket() {
        let p = MarketProfile.resolve(from: Locale(identifier: "de_AT"))
        XCTAssertEqual(p.market, .germany, "奥地利归德语区市场")
        XCTAssertEqual(p.privacyNarrativeStrength, .strong)
    }

    func testSwitzerlandAggregatesToGermanyMarket() {
        let p = MarketProfile.resolve(from: Locale(identifier: "de_CH"))
        XCTAssertEqual(p.market, .germany, "瑞士归德语区市场")
        XCTAssertEqual(p.privacyNarrativeStrength, .strong)
    }

    // MARK: - 英语区地区聚合

    func testEnglishRegionAggregation() {
        let regions = ["GB", "AU", "NZ", "CA", "IE", "SG"]
        for code in regions {
            let p = MarketProfile.resolve(from: Locale(identifier: "en_\(code)"))
            XCTAssertEqual(p.market, .english, "en_\(code) 应归 english 市场")
        }
    }

    // MARK: - 字体差异（语言层）与市场差异（地区层）独立性
    // 核心不变量：usesWenKai 只看 language+script，market 只看 region，互不影响。

    func testSimplifiedChineseInEnglishRegionStillUsesWenKai() {
        // 海外华人用户：系统语言 zh-Hans 但地区设为美国
        let p = MarketProfile.resolve(from: Locale(identifier: "zh-Hans_US"))
        XCTAssertEqual(p.market, .english, "地区 US → english 市场")
        XCTAssertTrue(p.usesWenKaiDisplay, "语言 zh-Hans → 仍应用文楷，与地区无关")
        XCTAssertEqual(p.privacyNarrativeStrength, .standard)
    }

    func testSimplifiedChineseInGermanyRegionStillUsesWenKai() {
        let p = MarketProfile.resolve(from: Locale(identifier: "zh-Hans_DE"))
        XCTAssertEqual(p.market, .germany)
        XCTAssertTrue(p.usesWenKaiDisplay, "语言 zh-Hans + 地区 DE → 文楷 + GDPR strong")
        XCTAssertEqual(p.privacyNarrativeStrength, .strong)
    }

    // MARK: - 未知/缺失地区

    func testUnknownRegionReturnsOther() {
        let p = MarketProfile.resolve(from: Locale(identifier: "en_BR"))
        XCTAssertEqual(p.market, .other)
        XCTAssertEqual(p.privacyNarrativeStrength, .standard)
    }

    func testNilRegionReturnsOther() {
        // Locale(identifier: "zh-Hans") 无 region
        let p = MarketProfile.resolve(from: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(p.market, .other, "无地区信息 → other")
        XCTAssertTrue(p.usesWenKaiDisplay, "无地区不影响语言层判断")
    }

    func testMarketFromNilRegionCode() {
        XCTAssertEqual(MarketProfile.Market.from(regionCode: nil), .other)
    }

    // MARK: - PrivacyStrength

    func testPrivacyStrengthIsStrong() {
        XCTAssertTrue(MarketProfile.PrivacyStrength.strong.isStrong)
        XCTAssertFalse(MarketProfile.PrivacyStrength.standard.isStrong)
    }

    // MARK: - Equatable / Sendable 结构不变量

    func testEquatableSameValues() {
        let a = MarketProfile(market: .japan, usesWenKaiDisplay: false, privacyNarrativeStrength: .standard)
        let b = MarketProfile(market: .japan, usesWenKaiDisplay: false, privacyNarrativeStrength: .standard)
        XCTAssertEqual(a, b)
    }

    func testEquatableDifferentMarket() {
        let a = MarketProfile(market: .japan, usesWenKaiDisplay: false, privacyNarrativeStrength: .standard)
        let b = MarketProfile(market: .korea, usesWenKaiDisplay: false, privacyNarrativeStrength: .standard)
        XCTAssertNotEqual(a, b)
    }
}
