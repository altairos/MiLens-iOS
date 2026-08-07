import XCTest
@testable import MiLens

/// P1.1：底部导航枚举 AppTab 纯逻辑测试。
/// 覆盖 Tab 顺序（对应 DESIGN.md §1 设计稿「首页 | 宠物 | 创作 | 我的」）、
/// rawValue 持久化稳定性（@AppStorage 存 rawValue）、图标非空。
final class AppTabTests: XCTestCase {
    func testTabOrderMatchesDesign() {
        XCTAssertEqual(AppTab.allCases, [.home, .pets, .create, .settings])
    }

    func testRawValuesAreStableForPersistence() {
        // @AppStorage("selectedTab") 以 rawValue 持久化，必须保持稳定。
        XCTAssertEqual(AppTab.home.rawValue, 0)
        XCTAssertEqual(AppTab.pets.rawValue, 1)
        XCTAssertEqual(AppTab.create.rawValue, 2)
        XCTAssertEqual(AppTab.settings.rawValue, 3)
    }

    func testRawValueRoundTrip() {
        for tab in AppTab.allCases {
            XCTAssertEqual(AppTab(rawValue: tab.rawValue), tab)
        }
    }

    func testSystemImageNotEmpty() {
        for tab in AppTab.allCases {
            XCTAssertFalse(tab.systemImage.isEmpty, "Tab \(tab) 缺少 SF Symbol 图标")
        }
    }
}

/// P1.1：路由枚举 Route 纯逻辑测试（DESIGN.md §6）。
/// 覆盖 NavigationStack 类型安全导航所需的 Hashable/Equatable 行为。
final class RouteTests: XCTestCase {
    func testSamePhotoViewAreEqual() {
        let id = UUID()
        XCTAssertEqual(Route.photoView(photoID: id), Route.photoView(photoID: id))
    }

    func testDifferentPhotoIDsNotEqual() {
        XCTAssertNotEqual(
            Route.photoView(photoID: UUID()),
            Route.photoView(photoID: UUID())
        )
    }

    func testDifferentCasesNotEqual() {
        let id = UUID()
        XCTAssertNotEqual(
            Route.photoView(photoID: id),
            Route.beadPattern(photoID: id)
        )
        let petID = UUID()
        XCTAssertNotEqual(
            Route.petProfile(petID: petID),
            Route.petEdit(petID: petID)
        )
    }

    func testRouteIsHashableForNavigationPath() {
        let route = Route.photoView(photoID: UUID())
        // 编译期即证明 Hashable；运行期确保可放入 Set。
        XCTAssertEqual(Set([route]).count, 1)
    }
}
