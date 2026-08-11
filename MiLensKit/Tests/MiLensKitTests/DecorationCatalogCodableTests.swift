import XCTest
@testable import MiLensKit

// DecorationCatalogCodableTests — 装饰目录 JSON 序列化与工厂分派测试。
// 覆盖：DecorationItem Codable 往返（含 ninePatchInsets / supportedRatios / fitMode）、
// createDecorationLayer 三种 fitMode 的几何输出（frame 铺满 / sticker 居中）。

final class DecorationCatalogCodableTests: XCTestCase {

    // MARK: - Codable 往返

    func testStretchItemRoundTrip() throws {
        let item = DecorationItem(
            id: "frame_plain_black", name: "纯黑",
            category: .frame, resourcePath: "frame_plain_black",
            previewPath: "frame_plain_black",
            isPremium: false, group: "基础", sortOrder: 1,
            fitMode: .stretch)
        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(DecorationItem.self, from: encoded)
        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.fitMode, .stretch)
        XCTAssertNil(decoded.ninePatchInsets)
        XCTAssertNil(decoded.supportedRatios)
    }

    func testNinePatchItemRoundTrip() throws {
        let insets = NinePatchInsets(top: 96, left: 96, bottom: 240, right: 96)
        let item = DecorationItem(
            id: "frame_polaroid_white", name: "拍立得白",
            category: .frame, resourcePath: "frame_polaroid_white",
            previewPath: "frame_polaroid_white",
            isPremium: true, group: "节日", sortOrder: 10,
            fitMode: .ninePatch, ninePatchInsets: insets)
        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(DecorationItem.self, from: encoded)
        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.fitMode, .ninePatch)
        XCTAssertEqual(decoded.ninePatchInsets, insets)
        XCTAssertTrue(decoded.isPremium)
    }

    func testRatioSetItemRoundTrip() throws {
        let item = DecorationItem(
            id: "frame_handdrawn_spring", name: "手绘春",
            category: .frame, resourcePath: "frame_handdrawn_spring",
            previewPath: "frame_handdrawn_spring",
            isPremium: false, group: "手绘", sortOrder: 20,
            fitMode: .ratioSet, supportedRatios: ["1x1", "3x4", "4x3", "16x9", "9x16"],
            nativeAspectRatio: 1.0)
        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(DecorationItem.self, from: encoded)
        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.fitMode, .ratioSet)
        XCTAssertEqual(decoded.supportedRatios, ["1x1", "3x4", "4x3", "16x9", "9x16"])
        XCTAssertEqual(decoded.nativeAspectRatio, 1.0)
    }

    func testStickerAlwaysStretchRegardlessOfFitMode() throws {
        // sticker 即使声明 ninePatch 也应被强制为 stretch
        let item = DecorationItem(
            id: "sticker_paw", name: "肉球",
            category: .sticker, resourcePath: "sticker_paw",
            previewPath: "sticker_paw",
            fitMode: .ninePatch)  // 声明 ninePatch
        XCTAssertEqual(item.fitMode, .stretch, "sticker 应强制 stretch")
    }

    func testStickerFitModeForcedStretchOnDecode() throws {
        // JSON 里 sticker 声明 ninePatch，自定义 init(from:) 应强制为 stretch
        // （防工具/手写 JSON 绕过自定义 init 的约束）
        let json = """
        {"id":"s","name":"S","category":"sticker","resourcePath":"s","previewPath":"s","fitMode":"ninePatch"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(DecorationItem.self, from: json)
        XCTAssertEqual(item.fitMode, .stretch, "Codable 反序列化也应强制 sticker=stretch")
    }

    func testDecodeToleratesMissingOptionalFields() throws {
        // V1.0 catalog.json 字段可能不全，自定义 init(from:) 用 decodeIfPresent 容错。
        let json = """
        {"id":"x","name":"X","category":"frame","resourcePath":"x","previewPath":"x"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(DecorationItem.self, from: json)
        XCTAssertEqual(item.fitMode, .stretch)   // 缺 fitMode 默认 stretch
        XCTAssertNil(item.ninePatchInsets)
        XCTAssertEqual(item.isPremium, false)    // 缺 isPremium 默认 false
        XCTAssertEqual(item.sortOrder, 0)        // 缺 sortOrder 默认 0
        XCTAssertEqual(item.group, "基础")
    }

    func testCatalogRoundTrip() throws {
        let catalog = DecorationCatalog(items: [
            DecorationItem(id: "a", name: "A", category: .frame,
                           resourcePath: "a", previewPath: "a", fitMode: .stretch),
            DecorationItem(id: "b", name: "B", category: .sticker,
                           resourcePath: "b", previewPath: "b"),
        ])
        let encoded = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(DecorationCatalog.self, from: encoded)
        XCTAssertEqual(decoded.items.count, 2)
        XCTAssertEqual(decoded.items.first?.id, "a")
    }

    // MARK: - JSON 字段名匹配（与 tools/frame_import.py 输出对齐）

    func testCatalogJsonFieldNameAlignment() throws {
        // 工具输出的字段名（camelCase）必须与 Codable 自动编码一致。
        let item = DecorationItem(
            id: "frame_x", name: "X", category: .frame,
            resourcePath: "frame_x", previewPath: "frame_x",
            isPremium: true, group: "G", sortOrder: 5,
            fitMode: .ninePatch,
            ninePatchInsets: NinePatchInsets(top: 1, left: 2, bottom: 3, right: 4))
        let encoded = try JSONEncoder().encode(item)
        let json = try XCTUnwrap(String(data: encoded, encoding: String.Encoding.utf8))
        // 关键字段名（与 tools/frame_import.py manifest_to_catalog_item 输出对齐）
        XCTAssertTrue(json.contains("\"resourcePath\""))
        XCTAssertTrue(json.contains("\"previewPath\""))
        XCTAssertTrue(json.contains("\"isPremium\""))
        XCTAssertTrue(json.contains("\"sortOrder\""))
        XCTAssertTrue(json.contains("\"fitMode\""))
        XCTAssertTrue(json.contains("\"ninePatchInsets\""))
        XCTAssertTrue(json.contains("\"supportedRatios\""))
        XCTAssertTrue(json.contains("\"nativeAspectRatio\""))
    }

    // MARK: - createDecorationLayer 分派

    func testFrameLayerFillsCanvas() {
        let item = DecorationItem(
            id: "frame_test", name: "T", category: .frame,
            resourcePath: "frame_test", previewPath: "frame_test",
            fitMode: .stretch)
        let layer = createDecorationLayer(from: item, canvasWidth: 200, canvasHeight: 300)
        XCTAssertEqual(layer.type, .frame)
        XCTAssertEqual(layer.width, 200, accuracy: 1e-9)
        XCTAssertEqual(layer.height, 300, accuracy: 1e-9)
        XCTAssertEqual(layer.x, 0, accuracy: 1e-9)
        XCTAssertEqual(layer.y, 0, accuracy: 1e-9)
        XCTAssertEqual(layer.resourcePath, "frame_test")
    }

    func testFrameLayerGeometryIgnoresFitMode() {
        // fitMode 不影响 layer 几何（铺满），仅影响渲染分块
        let stretch = createDecorationLayer(
            from: DecorationItem(id: "f1", name: "F1", category: .frame,
                                 resourcePath: "f1", previewPath: "f1", fitMode: .stretch),
            canvasWidth: 100, canvasHeight: 100)
        let ninePatch = createDecorationLayer(
            from: DecorationItem(id: "f2", name: "F2", category: .frame,
                                 resourcePath: "f2", previewPath: "f2", fitMode: .ninePatch,
                                 ninePatchInsets: NinePatchInsets(top: 10, left: 10, bottom: 10, right: 10)),
            canvasWidth: 100, canvasHeight: 100)
        let ratioSet = createDecorationLayer(
            from: DecorationItem(id: "f3", name: "F3", category: .frame,
                                 resourcePath: "f3", previewPath: "f3", fitMode: .ratioSet,
                                 supportedRatios: ["1x1"]),
            canvasWidth: 100, canvasHeight: 100)
        // 三种 fitMode 的几何尺寸都铺满画布
        for layer in [stretch, ninePatch, ratioSet] {
            XCTAssertEqual(layer.width, 100, accuracy: 1e-9)
            XCTAssertEqual(layer.height, 100, accuracy: 1e-9)
        }
    }

    func testStickerLayerCentered() {
        let item = DecorationItem(
            id: "sticker_paw", name: "肉球", category: .sticker,
            resourcePath: "sticker_paw", previewPath: "sticker_paw")
        // 画布 200x400，短边 200，stickerSize = 200*0.3 = 60
        let layer = createDecorationLayer(from: item, canvasWidth: 200, canvasHeight: 400)
        XCTAssertEqual(layer.type, .sticker)
        XCTAssertEqual(layer.width, 60, accuracy: 1e-9)
        XCTAssertEqual(layer.height, 60, accuracy: 1e-9)
        // 居中：(200-60)/2 = 70, (400-60)/2 = 170
        XCTAssertEqual(layer.x, 70, accuracy: 1e-9)
        XCTAssertEqual(layer.y, 170, accuracy: 1e-9)
    }

    // MARK: - catalog 查询

    func testItemsForCategorySortsBySortOrder() {
        let catalog = DecorationCatalog(items: [
            DecorationItem(id: "b", name: "B", category: .frame,
                           resourcePath: "b", previewPath: "b", sortOrder: 20),
            DecorationItem(id: "a", name: "A", category: .frame,
                           resourcePath: "a", previewPath: "a", sortOrder: 10),
            DecorationItem(id: "s", name: "S", category: .sticker,
                           resourcePath: "s", previewPath: "s", sortOrder: 1),
        ])
        let frames = catalog.items(for: .frame)
        XCTAssertEqual(frames.map(\.id), ["a", "b"], "按 sortOrder 升序")
    }

    func testUsableItemsFiltersPremiumForNonPro() {
        let catalog = DecorationCatalog(items: [
            DecorationItem(id: "free", name: "F", category: .frame,
                           resourcePath: "free", previewPath: "free", isPremium: false),
            DecorationItem(id: "pro", name: "P", category: .frame,
                           resourcePath: "pro", previewPath: "pro", isPremium: true),
        ])
        XCTAssertEqual(catalog.usableItems(for: .frame, isPro: false).map(\.id), ["free"])
        XCTAssertEqual(catalog.usableItems(for: .frame, isPro: true).map(\.id).sorted(),
                       ["free", "pro"])
    }
}
