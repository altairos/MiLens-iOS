//  MiLensUITests —— UI 冒烟测试（评审阻塞项：工程此前只有单元测试 target）。
//
//  覆盖：冷启动进入主界面、4 Tab 导航、空库页面状态渲染。
//  运行方式：Mac 上 xcodegen generate 后选择 MiLens scheme → Test（包含 MiLensUITests）。
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

        for title in ["首页", "宠物", "创作", "我的"] {
            XCTAssertTrue(
                app.tabBars.buttons[title].waitForExistence(timeout: 5),
                "底部 Tab 缺失：\(title)"
            )
        }
    }

    /// Tab 导航冒烟：依次切换各 Tab，断言页面内容实际渲染（空库状态文案）。
    func testTabNavigationShowsEachScreen() {
        let app = launchApp()

        // 宠物（Tab 2）：空库 → 空状态引导文案
        app.tabBars.buttons["宠物"].tap()
        XCTAssertTrue(
            app.staticTexts["还没有伙伴档案"].waitForExistence(timeout: 5),
            "宠物页空状态未渲染"
        )

        // 创作（Tab 3）：空库 → 「先保存一张照片」引导
        app.tabBars.buttons["创作"].tap()
        XCTAssertTrue(
            app.staticTexts["先保存一张照片"].waitForExistence(timeout: 5),
            "创作页空状态未渲染"
        )

        // 首页（Tab 1）：返回后主界面仍在
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(
            app.tabBars.buttons["创作"].waitForExistence(timeout: 5),
            "切回首页后 Tab 栏异常"
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
}
