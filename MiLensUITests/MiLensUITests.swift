//  MiLensUITests —— UI 冒烟测试（评审阻塞项：工程此前只有单元测试 target）。
//
//  覆盖：冷启动进入主界面、4 Tab 导航、空库页面状态渲染、创作页→相册扫描入口、
//  宠物建档 sheet 开合、设置页备份入口可见性、非 Pro 点备份导出弹付费墙并可关闭
//  （audit-6 §4 P2-2：冒烟清单从 2 条扩到 6 条）。
//  运行方式：Mac 上 xcodegen generate 后选择 MiLens scheme → Test（包含 MiLensUITests）。
//
//  断言约定：元素以 accessibilityIdentifier 定位（源码侧用同名 loc key 标注，
//  AddPetSheet 取消按钮用 addpet.cancel 限定），不按中文文案断言——多语言下
//  文案随 locale 变化（audit N6 迁移）。
//
//  环境说明：launchEnvironment 注入 XCTestConfigurationFilePath 触发 App 的
//  isTesting 路径（MiLensApp.init）——in-memory 容器 + 跳过 onboarding + mock Store，
//  与单元测试 host 环境语义一致，保证冒烟用例不依赖本地 UserDefaults/相册授权。

import XCTest

final class MiLensUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 冷启动冒烟：App 进入主界面（RootTabView），4 个 Tab 齐全。
    func testLaunchShowsFourTabs() {
        let app = launchApp()

        let tabs = [
            ("tab.home", "首页"),
            ("tab.pets", "宠物"),
            ("tab.create", "创作"),
            ("tab.settings", "我的"),
        ]

        for (identifier, title) in tabs {
            XCTAssertTrue(
                app.buttons[identifier].waitForExistence(timeout: 5),
                "底部 Tab 缺失：\(title)"
            )
        }
        XCTAssertEqual(
            tabs.filter { app.buttons[$0.0].isSelected }.count,
            1,
            "底部导航应且仅应有一个选中项"
        )
    }

    /// Tab 导航冒烟：依次切换各 Tab，断言页面内容实际渲染（空库状态文案）。
    func testTabNavigationShowsEachScreen() {
        let app = launchApp()

        // 宠物（Tab 2）：空库 → 空状态引导文案
        app.buttons["tab.pets"].tap()
        XCTAssertTrue(app.buttons["tab.pets"].isSelected, "宠物 Tab 未进入选中态")
        XCTAssertTrue(
            app.staticTexts["pets.empty.title"].waitForExistence(timeout: 5),
            "宠物页空状态未渲染"
        )

        // 创作（Tab 3）：空库 → 「先保存一张照片」引导
        app.buttons["tab.create"].tap()
        XCTAssertTrue(app.buttons["tab.create"].isSelected, "创作 Tab 未进入选中态")
        XCTAssertTrue(
            app.staticTexts["create.empty.title"].waitForExistence(timeout: 5),
            "创作页空状态未渲染"
        )

        // 首页（Tab 1）：返回后主界面仍在
        app.buttons["tab.home"].tap()
        XCTAssertTrue(
            app.buttons["tab.home"].isSelected,
            "切回首页后 Tab 栏异常"
        )
    }

    /// 扫描入口冒烟：创作页空态 → 「去相册添加」push 相册页 → 空态 + 「开始扫描」入口。
    /// 只断言入口存在，不点击「开始扫描」——会触发真实相册授权（isTesting 下
    /// photoLibrary 为真实 IOSPhotoLibraryAccess，系统弹窗会阻塞用例）。
    func testCreateTabNavigatesToGalleryScanEntry() {
        let app = launchApp()

        app.buttons["tab.create"].tap()
        let galleryLink = app.buttons["create.empty.cta"]
        XCTAssertTrue(
            galleryLink.waitForExistence(timeout: 5),
            "创作页空态缺少「去相册添加」入口"
        )
        galleryLink.tap()

        XCTAssertTrue(
            app.staticTexts["gallery.empty.title"].waitForExistence(timeout: 5),
            "相册页空状态未渲染"
        )
        XCTAssertTrue(
            app.buttons["gallery.empty.cta"].exists,
            "相册页空态缺少「开始扫描」入口"
        )
    }

    /// 建档 sheet 开合冒烟：宠物页空态 → 「添加伙伴」弹 sheet（取消可见）→ 取消后关闭。
    func testPetsAddSheetOpensAndCancels() {
        let app = launchApp()

        app.buttons["tab.pets"].tap()
        XCTAssertTrue(
            app.buttons["pets.empty.cta"].waitForExistence(timeout: 5),
            "宠物页空态缺少「添加伙伴」按钮"
        )
        app.buttons["pets.empty.cta"].firstMatch.tap()

        // sheet 弹出：导航栏「取消」按钮出现（AddPetSheet toolbar）
        let cancelButton = app.buttons["addpet.cancel"]
        XCTAssertTrue(
            cancelButton.waitForExistence(timeout: 5),
            "添加伙伴 sheet 未弹出或缺少取消按钮"
        )

        cancelButton.tap()
        // 取消后 sheet 关闭，空态文案重新可见
        XCTAssertFalse(
            app.buttons["addpet.cancel"].waitForExistence(timeout: 3),
            "取消后 sheet 未关闭"
        )
        XCTAssertTrue(
            app.staticTexts["pets.empty.title"].waitForExistence(timeout: 5),
            "取消建档后宠物页空状态未恢复"
        )
    }

    /// 设置页备份入口可见性冒烟：「备份导出」「备份恢复」两行在滚动后可达。
    /// isTesting 下注入真实 ZipBackupService（isAvailable == true），入口不禁用。
    func testSettingsBackupEntriesVisible() {
        let app = launchApp()

        app.buttons["tab.settings"].tap()
        let exportEntry = app.buttons["settings.backup.export"]
        XCTAssertTrue(
            exportEntry.waitForExistence(timeout: 5),
            "设置页未渲染"
        )
        scrollToElement(exportEntry, in: app)
        XCTAssertTrue(
            exportEntry.isHittable,
            "滚动后「备份导出」行仍不可达"
        )
        XCTAssertTrue(
            app.buttons["settings.backup.restore"].exists,
            "「备份恢复」行缺失"
        )
    }

    /// 付费墙冒烟：非 Pro（MockStoreService inactive）点「备份导出」→ 弹付费墙
    /// （MockStoreService 默认注入 sampleProducts，ready 态渲染）→ 关闭后返回。
    func testSettingsBackupExportShowsPaywall() {
        let app = launchApp()

        app.buttons["tab.settings"].tap()
        let exportEntry = app.buttons["settings.backup.export"]
        XCTAssertTrue(exportEntry.waitForExistence(timeout: 5), "设置页未渲染")
        scrollToElement(exportEntry, in: app)
        exportEntry.tap()

        // 付费墙 sheet：ready 态才渲染关闭按钮（identifier "paywall.close"，付费墙
        // 独有；勿用 "MiLens Pro"——设置页 ProHeroCard 首屏同名文本会使断言恒真）。
        // 勿按 hero 文案断言：paywall.hero.title 为多行文本（label 含换行，匹配不稳）；
        // 上一版误用无代码引用的孤儿文案 paywall.title，CI 首跑即失败。
        let closeButton = app.buttons["paywall.close"].firstMatch
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 10),
            "非 Pro 点「备份导出」未弹出付费墙"
        )

        closeButton.tap()
        XCTAssertFalse(
            app.buttons["paywall.close"].waitForExistence(timeout: 3),
            "点关闭后付费墙未关闭"
        )
        // 返回设置页后备份入口仍在
        scrollToElement(exportEntry, in: app)
        XCTAssertTrue(exportEntry.exists, "关闭付费墙后设置页备份入口丢失"
        )
    }

    // MARK: - 基础设施

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // 触发 isTesting 路径：in-memory 容器 + 跳过 onboarding（与单测 host 语义一致）。
        app.launchEnvironment["XCTestConfigurationFilePath"] = "/dev/null"
        app.launch()
        return app
    }

    /// 滚动直到元素可点击（设置页为长 Form，备份行在首屏之外）。
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable, swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }
}
