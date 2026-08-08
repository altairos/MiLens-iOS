import XCTest
import StoreKitTest
@testable import MiLens

/// Products.storekit 本地配置验证（UI Rework 4.5 / DEVELOPMENT.md §4.4）。
///
/// 两层确定性验证（不依赖 StoreKit 测试守护进程）：
/// 1. SKTestSession 以文件内容初始化——schema 不合法时初始化抛错；
/// 2. JSON 内容断言——产品 ID 齐全、displayPrice 非空（P0-4：UI 不硬编码价格的前提）、
///    订阅带 7 天（P1W）免费试用 introductoryOffer。
///
/// 未覆盖：Product.products 经 SKTestSession 的运行时加载——本机模拟器
/// StoreKit 测试守护进程报 SKInternalErrorDomain Code=3（配置无法安装到会话），
/// 属环境问题而非配置问题；端到端购买/恢复走 scheme 关联 .storekit 后人工验证
/// （Xcode Scheme Editor → Run/Test → Options → StoreKit Configuration）。
final class StoreKitConfigurationTests: XCTestCase {

    private func configURL() throws -> URL {
        let url = Bundle.main.url(forResource: "Products", withExtension: "storekit")
        return try XCTUnwrap(url, "Products.storekit 未打入 App Bundle")
    }

    /// SKTestSession 初始化即解析校验：schema 不合法会抛错。
    func testConfigurationParsesViaSKTestSession() throws {
        _ = try SKTestSession(contentsOf: try configURL())
    }

    /// JSON 内容断言：产品齐全、价格存在、订阅试用为 7 天免费。
    func testConfigurationContents() throws {
        let data = try Data(contentsOf: try configURL())
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // 永久买断：非消耗品
        let products = try XCTUnwrap(root["products"] as? [[String: Any]])
        let nonConsumables = products.filter { $0["type"] as? String == "NonConsumable" }
        XCTAssertEqual(
            nonConsumables.compactMap { $0["productID"] as? String },
            [MiLensProducts.lifetime]
        )
        XCTAssertFalse((nonConsumables.first?["displayPrice"] as? String ?? "").isEmpty)

        // 订阅组：月度 + 年度
        let groups = try XCTUnwrap(root["subscriptionGroups"] as? [[String: Any]])
        let group = try XCTUnwrap(groups.first)
        let subs = try XCTUnwrap(group["subscriptions"] as? [[String: Any]])
        XCTAssertEqual(
            Set(subs.compactMap { $0["productID"] as? String }),
            [MiLensProducts.monthly, MiLensProducts.yearly]
        )

        for sub in subs {
            let id = sub["productID"] as? String ?? ""
            // 价格必须来自配置（P0-4）
            XCTAssertFalse((sub["displayPrice"] as? String ?? "").isEmpty, "\(id) 缺少 displayPrice")
            // 免费试用 7 天（P1W）
            let intro = try XCTUnwrap(sub["introductoryOffer"] as? [String: Any], "\(id) 缺少试用")
            XCTAssertEqual(intro["paymentMode"] as? String, "free", id)
            XCTAssertEqual(intro["subscriptionPeriod"] as? String, "P1W", id)
            // 自动续费周期合法
            let period = sub["recurringSubscriptionPeriod"] as? String ?? ""
            XCTAssertTrue(period == "P1M" || period == "P1Y", "\(id) 周期异常: \(period)")
        }
    }
}
