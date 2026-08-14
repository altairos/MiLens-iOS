import XCTest
@testable import MiLensKit

// DecorationAssetResolverTests — 装饰素材 resourcePath 解析测试。
// 覆盖：stretch/ninePatch/sticker 原样；ratioSet 全比例精确匹配、越界最近匹配；
// 空候选 / 非法 targetRatio / 非法 token 兜底回退。

final class DecorationAssetResolverTests: XCTestCase {

    private func ratioSetItem(ratios: [String]?) -> DecorationItem {
        DecorationItem(
            id: "frame_multi", name: "M", category: .frame,
            resourcePath: "frame_multi", previewPath: "frame_multi",
            fitMode: .ratioSet, supportedRatios: ratios)
    }

    private let fullRatios = ["1x1", "3x4", "4x3", "16x9", "9x16"]

    // MARK: - 非 ratioSet 原样返回

    func testStretchReturnsResourcePath() {
        let item = DecorationItem(
            id: "f", name: "F", category: .frame,
            resourcePath: "frame_plain", previewPath: "frame_plain", fitMode: .stretch)
        XCTAssertEqual(resolveDecorationResource(item: item, targetRatio: 0.75), "frame_plain")
    }

    func testNinePatchReturnsResourcePath() {
        let item = DecorationItem(
            id: "f", name: "F", category: .frame,
            resourcePath: "frame_polaroid", previewPath: "frame_polaroid",
            fitMode: .ninePatch,
            ninePatchInsets: NinePatchInsets(top: 10, left: 10, bottom: 10, right: 10))
        XCTAssertEqual(resolveDecorationResource(item: item, targetRatio: 1.0), "frame_polaroid")
    }

    func testStickerAlwaysStretch() {
        // sticker 恒 stretch（DecorationItem 强制），任何比例都原样
        let item = DecorationItem(
            id: "s", name: "S", category: .sticker,
            resourcePath: "sticker_paw", previewPath: "sticker_paw")
        XCTAssertEqual(resolveDecorationResource(item: item, targetRatio: 0.5625), "sticker_paw")
    }

    // MARK: - ratioSet 精确匹配

    func testExactRatioMatchesEachToken() {
        let cases: [(Double, String)] = [
            (1.0, "1x1"),
            (3.0 / 4.0, "3x4"),
            (4.0 / 3.0, "4x3"),
            (16.0 / 9.0, "16x9"),
            (9.0 / 16.0, "9x16"),
        ]
        for (ratio, token) in cases {
            XCTAssertEqual(
                resolveDecorationResource(item: ratioSetItem(ratios: fullRatios), targetRatio: ratio),
                "frame_multi_\(token)", "ratio=\(ratio)")
        }
    }

    func testIntermediateRatioPicksClosest() {
        // 1.2：|1.2-1.333|=0.133 < |1.2-1.0|=0.2 → 4x3
        XCTAssertEqual(
            resolveDecorationResource(item: ratioSetItem(ratios: fullRatios), targetRatio: 1.2),
            "frame_multi_4x3")
        // 0.9：|0.9-1.0|=0.1 < |0.9-0.75|=0.15 → 1x1
        XCTAssertEqual(
            resolveDecorationResource(item: ratioSetItem(ratios: fullRatios), targetRatio: 0.9),
            "frame_multi_1x1")
    }

    func testOutOfBoundsRatioPicksNearest() {
        // 2.5 超出最大候选（16x9≈1.778）：仍选最近的 16x9
        XCTAssertEqual(
            resolveDecorationResource(item: ratioSetItem(ratios: fullRatios), targetRatio: 2.5),
            "frame_multi_16x9")
        // 0.4 低于最小候选（9x16=0.5625）：选 9x16
        XCTAssertEqual(
            resolveDecorationResource(item: ratioSetItem(ratios: fullRatios), targetRatio: 0.4),
            "frame_multi_9x16")
    }

    // MARK: - 兜底回退

    func testEmptyOrNilRatiosFallsBack() {
        XCTAssertEqual(
            resolveDecorationResource(item: ratioSetItem(ratios: nil), targetRatio: 1.0),
            "frame_multi")
        XCTAssertEqual(
            resolveDecorationResource(item: ratioSetItem(ratios: []), targetRatio: 1.0),
            "frame_multi")
    }

    func testInvalidTargetRatioFallsBack() {
        // 非法 targetRatio（0/负/NaN）：无有效基准，原样返回
        let item = ratioSetItem(ratios: fullRatios)
        XCTAssertEqual(resolveDecorationResource(item: item, targetRatio: 0), "frame_multi")
        XCTAssertEqual(resolveDecorationResource(item: item, targetRatio: -1), "frame_multi")
        XCTAssertEqual(resolveDecorationResource(item: item, targetRatio: .nan), "frame_multi")
    }

    func testInvalidTokensSkipped() {
        // 非法 token 跳过，只在合法候选中选最近
        let item = ratioSetItem(ratios: ["axb", "3x4"])
        XCTAssertEqual(
            resolveDecorationResource(item: item, targetRatio: 1.0), "frame_multi_3x4")
    }

    func testAllTokensInvalidFallsBack() {
        let item = ratioSetItem(ratios: ["axb", "0x0"])
        XCTAssertEqual(
            resolveDecorationResource(item: item, targetRatio: 1.0), "frame_multi")
    }
}
