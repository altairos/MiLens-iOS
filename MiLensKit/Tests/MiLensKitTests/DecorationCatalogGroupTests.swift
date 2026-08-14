import XCTest
@testable import MiLensKit

// DecorationCatalogGroupTests — 分组稳定 ID 与稳定排序测试（阻塞项8）。
// 覆盖：groups(for:) 按 DecorationGroupIds 常量序返回（recommended 恒首位）、
// 未知分组字母序追加、组内 sortOrder 升序、类别隔离、默认 group 值。

final class DecorationCatalogGroupTests: XCTestCase {

    private func item(
        _ id: String, _ category: DecorationCategory, group: String, sortOrder: Int = 0
    ) -> DecorationItem {
        DecorationItem(
            id: id, name: id, category: category,
            resourcePath: id, previewPath: id, group: group, sortOrder: sortOrder)
    }

    // MARK: - 稳定分组顺序

    func testFrameGroupsInStableOrder() {
        // 乱序构造（recommended 的 sortOrder 最大仍首位）
        let catalog = DecorationCatalog(items: [
            item("h1", .frame, group: "holiday", sortOrder: 3),
            item("r1", .frame, group: "recommended", sortOrder: 99),
            item("p1", .frame, group: "paper", sortOrder: 1),
            item("f1", .frame, group: "film", sortOrder: 2),
        ])
        let groups = catalog.groups(for: .frame)
        XCTAssertEqual(groups.map(\.id), ["recommended", "film", "paper", "holiday"])
        // recommended 恒首位
        XCTAssertEqual(groups.first?.id, "recommended")
    }

    func testStickerGroupsInStableOrder() {
        let catalog = DecorationCatalog(items: [
            item("m1", .sticker, group: "memorial"),
            item("d1", .sticker, group: "daily"),
            item("p1", .sticker, group: "paw"),
            item("r1", .sticker, group: "recommended"),
        ])
        XCTAssertEqual(
            catalog.groups(for: .sticker).map(\.id),
            ["recommended", "paw", "daily", "memorial"])
    }

    func testUnknownGroupsAppendedAlphabetically() {
        // 脏数据容错：未知分组不丢弃，按字母序追加在已知分组之后
        let catalog = DecorationCatalog(items: [
            item("z1", .frame, group: "zebra"),
            item("a1", .frame, group: "alpha"),
            item("k1", .frame, group: "film"),
        ])
        XCTAssertEqual(
            catalog.groups(for: .frame).map(\.id), ["film", "alpha", "zebra"])
    }

    func testEmptyGroupOmitted() {
        // 声明序中存在但没有条目的分组不出现
        let catalog = DecorationCatalog(items: [item("f1", .frame, group: "film")])
        XCTAssertEqual(catalog.groups(for: .frame).map(\.id), ["film"])
    }

    func testItemsWithinGroupSortedBySortOrder() {
        let catalog = DecorationCatalog(items: [
            item("b", .sticker, group: "paw", sortOrder: 20),
            item("c", .sticker, group: "paw", sortOrder: 30),
            item("a", .sticker, group: "paw", sortOrder: 10),
        ])
        let paw = catalog.groups(for: .sticker).first { $0.id == "paw" }
        XCTAssertEqual(paw?.items.map(\.id), ["a", "b", "c"])
    }

    func testGroupsSeparateCategories() {
        // groups(for: .frame) 不含 sticker 条目，反之亦然
        let catalog = DecorationCatalog(items: [
            item("f1", .frame, group: "film"),
            item("s1", .sticker, group: "paw"),
        ])
        XCTAssertEqual(catalog.groups(for: .frame).map(\.id), ["film"])
        XCTAssertEqual(catalog.groups(for: .frame).flatMap(\.items).map(\.id), ["f1"])
        XCTAssertEqual(catalog.groups(for: .sticker).flatMap(\.items).map(\.id), ["s1"])
    }

    func testEmptyCatalogReturnsNoGroups() {
        XCTAssertTrue(DecorationCatalog.empty.groups(for: .frame).isEmpty)
        XCTAssertTrue(DecorationCatalog.empty.groups(for: .sticker).isEmpty)
    }

    // MARK: - 默认值与常量

    func testDefaultGroupIsRecommended() {
        // init 缺 group 参数 → recommended（阻塞项8：旧默认值"基础"废弃）
        let item = DecorationItem(
            id: "x", name: "X", category: .frame, resourcePath: "x", previewPath: "x")
        XCTAssertEqual(item.group, "recommended")
    }

    func testGroupIdsConstantsMatchPlan() {
        // 计划 §5.1 分组清单（UI 顺序即声明顺序）
        XCTAssertEqual(DecorationGroupIds.frame, ["recommended", "film", "paper", "holiday"])
        XCTAssertEqual(DecorationGroupIds.sticker, ["recommended", "paw", "daily", "memorial"])
        XCTAssertTrue(DecorationGroupIds.isKnownId("film", category: .frame))
        XCTAssertFalse(DecorationGroupIds.isKnownId("paw", category: .frame))
        XCTAssertFalse(DecorationGroupIds.isKnownId("film", category: .sticker))
    }

    func testStickerFitModeAlwaysStretch() {
        // sticker 恒 stretch：即使构造时误传 fitMode（catalog 层面再守一道）
        let sticker = DecorationItem(
            id: "s", name: "S", category: .sticker,
            resourcePath: "s", previewPath: "s", fitMode: .ninePatch)
        XCTAssertEqual(sticker.fitMode, .stretch)
    }
}
