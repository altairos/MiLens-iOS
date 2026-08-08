import XCTest
@testable import MiLens

/// SettingsLogic 测试：外观模式解析/回退、版本号组成部分、纪念提醒开关决策、
/// 字体许可数据与外链常量完整性（OFL 合规与隐私政策链接的唯一事实来源）。
final class SettingsLogicTests: XCTestCase {

    // MARK: - 外观模式

    func testParseKnownAppearanceModes() {
        XCTAssertEqual(AppearanceMode.parse("system"), .system)
        XCTAssertEqual(AppearanceMode.parse("light"), .light)
        XCTAssertEqual(AppearanceMode.parse("dark"), .dark)
    }

    func testParseUnknownRawValueFallsBackToSystem() {
        XCTAssertEqual(AppearanceMode.parse("sepia"), .system)
        XCTAssertEqual(AppearanceMode.parse(""), .system)
    }

    func testAppearanceModeAllCasesRawValuesRoundTrip() {
        for mode in AppearanceMode.allCases {
            XCTAssertEqual(AppearanceMode.parse(mode.rawValue), mode)
        }
    }

    // MARK: - 版本号

    func testVersionPartsPassThroughWhenPresent() {
        let parts = SettingsLogic.versionParts(marketing: "1.0", build: "42")
        XCTAssertEqual(parts.marketing, "1.0")
        XCTAssertEqual(parts.build, "42")
    }

    func testVersionPartsFallbackWhenMissing() {
        let parts = SettingsLogic.versionParts(marketing: nil, build: nil)
        XCTAssertEqual(parts.marketing, "-")
        XCTAssertEqual(parts.build, "-")
    }

    // MARK: - 纪念提醒开关决策

    func testReminderToggleOffCancelsAll() {
        XCTAssertEqual(
            SettingsLogic.resolveReminderToggle(enabled: false, authorized: true),
            .cancelAll
        )
        XCTAssertEqual(
            SettingsLogic.resolveReminderToggle(enabled: false, authorized: false),
            .cancelAll
        )
    }

    func testReminderToggleOnAuthorizedSchedules() {
        XCTAssertEqual(
            SettingsLogic.resolveReminderToggle(enabled: true, authorized: true),
            .schedule
        )
    }

    func testReminderToggleOnDeniedRollsBack() {
        XCTAssertEqual(
            SettingsLogic.resolveReminderToggle(enabled: true, authorized: false),
            .rollbackAndPrompt
        )
    }

    // MARK: - 字体许可与外链

    func testFontCreditsCoverBothEmbeddedFontsWithOFL() {
        let names = SettingsLogic.fontCredits.map(\.name)
        XCTAssertEqual(names.count, 2)
        XCTAssertTrue(names.contains { $0.contains("霞鹜文楷") })
        XCTAssertTrue(names.contains { $0.contains("Fraunces") })
        for credit in SettingsLogic.fontCredits {
            XCTAssertTrue(credit.licenseName.contains("SIL Open Font License"))
            XCTAssertNotNil(URL(string: credit.sourceURL))
        }
    }

    func testLinksAreValidAndMatchMetadata() {
        XCTAssertTrue(SettingsLogic.Links.privacyPolicy.contains("miovelle.cn"))
        XCTAssertNotNil(URL(string: SettingsLogic.Links.privacyPolicy))
        XCTAssertNotNil(URL(string: SettingsLogic.Links.termsOfService))
        XCTAssertNotNil(URL(string: SettingsLogic.Links.manageSubscriptions))
    }
}
