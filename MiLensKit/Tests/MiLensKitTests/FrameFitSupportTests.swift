import XCTest
@testable import MiLensKit

// FrameFitSupportTests — 相框自适应核心逻辑测试。
// 覆盖：computeNinePatchTiles 九宫格几何（标准/退化/比例缩放）、
// parseAspectRatioToken、pickClosestAspectRatio、NinePatchInsets.isValid。

final class FrameFitSupportTests: XCTestCase {

    // MARK: - NinePatchInsets.isValid

    func testInsetsValidForReasonableValues() {
        let insets = NinePatchInsets(top: 10, left: 10, bottom: 20, right: 10)
        XCTAssertTrue(insets.isValid(srcWidth: 100, srcHeight: 100))
    }

    func testInsetsInvalidWhenSumExceedsSize() {
        let insets = NinePatchInsets(top: 60, left: 10, bottom: 60, right: 10)
        // top+bottom(120) >= srcHeight(100) → 非法
        XCTAssertFalse(insets.isValid(srcWidth: 100, srcHeight: 100))
    }

    func testInsetsInvalidForZeroSize() {
        let insets = NinePatchInsets(top: 1, left: 1, bottom: 1, right: 1)
        XCTAssertFalse(insets.isValid(srcWidth: 0, srcHeight: 0))
    }

    // MARK: - computeNinePatchTiles 标准布局

    func testStandardNinePatchReturnsNineTiles() {
        let tiles = computeNinePatchTiles(
            srcWidth: 100, srcHeight: 100,
            insets: NinePatchInsets(top: 10, left: 10, bottom: 10, right: 10),
            dstX: 0, dstY: 0, dstW: 200, dstH: 200)
        XCTAssertEqual(tiles.count, 9, "标准 ninePatch 应返回 9 块")
    }

    func testCornerTilesAreFixedSize() {
        // src 100x100 inset=10，目标 200x200（2 倍缩放）
        let tiles = computeNinePatchTiles(
            srcWidth: 100, srcHeight: 100,
            insets: NinePatchInsets(top: 10, left: 10, bottom: 10, right: 10),
            dstX: 0, dstY: 0, dstW: 200, dstH: 200)
        // 左上角（index 0）：src 10x10，dst 20x20（inset 按比例缩放）
        XCTAssertEqual(tiles[0].srcW, 10, accuracy: 1e-9)
        XCTAssertEqual(tiles[0].srcH, 10, accuracy: 1e-9)
        XCTAssertEqual(tiles[0].dstW, 20, accuracy: 1e-9)
        XCTAssertEqual(tiles[0].dstH, 20, accuracy: 1e-9)
        // 右下角（index 8）：src 10x10，dst 20x20
        XCTAssertEqual(tiles[8].srcW, 10, accuracy: 1e-9)
        XCTAssertEqual(tiles[8].dstW, 20, accuracy: 1e-9)
        XCTAssertEqual(tiles[8].dstX, 180, accuracy: 1e-9)  // 200 - 20
        XCTAssertEqual(tiles[8].dstY, 180, accuracy: 1e-9)
    }

    func testCenterTileCoversInnerWindow() {
        // src 100x100 inset=10，目标 200x200
        let tiles = computeNinePatchTiles(
            srcWidth: 100, srcHeight: 100,
            insets: NinePatchInsets(top: 10, left: 10, bottom: 10, right: 10),
            dstX: 0, dstY: 0, dstW: 200, dstH: 200)
        // 中央块（index 4）：src 80x80（100-10-10），dst 160x160（200-20-20）
        let center = tiles[4]
        XCTAssertEqual(center.srcX, 10, accuracy: 1e-9)
        XCTAssertEqual(center.srcY, 10, accuracy: 1e-9)
        XCTAssertEqual(center.srcW, 80, accuracy: 1e-9)
        XCTAssertEqual(center.srcH, 80, accuracy: 1e-9)
        XCTAssertEqual(center.dstX, 20, accuracy: 1e-9)
        XCTAssertEqual(center.dstY, 20, accuracy: 1e-9)
        XCTAssertEqual(center.dstW, 160, accuracy: 1e-9)
        XCTAssertEqual(center.dstH, 160, accuracy: 1e-9)
    }

    func testTopEdgeStretchesHorizontallyOnly() {
        // 上边（index 1）：src 宽 80（100-10-10）高 10（top inset）
        // dst 宽 160（200-20-20）高 20（10*2）
        let tiles = computeNinePatchTiles(
            srcWidth: 100, srcHeight: 100,
            insets: NinePatchInsets(top: 10, left: 10, bottom: 10, right: 10),
            dstX: 0, dstY: 0, dstW: 200, dstH: 200)
        let top = tiles[1]
        XCTAssertEqual(top.srcH, 10, accuracy: 1e-9)   // 高度不变（= top inset）
        XCTAssertEqual(top.dstH, 20, accuracy: 1e-9)   // 高度按 Y 缩放（2 倍）
        XCTAssertEqual(top.srcW, 80, accuracy: 1e-9)
        XCTAssertEqual(top.dstW, 160, accuracy: 1e-9)  // 宽度填充
    }

    func testDestinationOffsetShiftsAllTiles() {
        // dstX=100, dstY=50 时，所有 tile 的 dst 坐标应相应偏移
        let tiles = computeNinePatchTiles(
            srcWidth: 100, srcHeight: 100,
            insets: NinePatchInsets(top: 10, left: 10, bottom: 10, right: 10),
            dstX: 100, dstY: 50, dstW: 200, dstH: 200)
        // 左上角的 dstX 应 = 100（= dstX）
        XCTAssertEqual(tiles[0].dstX, 100, accuracy: 1e-9)
        XCTAssertEqual(tiles[0].dstY, 50, accuracy: 1e-9)
        // 右下角的 dstX 应 = 100 + 200 - 20 = 280
        XCTAssertEqual(tiles[8].dstX, 280, accuracy: 1e-9)
    }

    // MARK: - 退化场景

    func testInvalidInsetsDegradesToSingleStretchTile() {
        // top+bottom >= srcHeight → 非法 inset，退化为单块整图拉伸
        let tiles = computeNinePatchTiles(
            srcWidth: 100, srcHeight: 100,
            insets: NinePatchInsets(top: 60, left: 10, bottom: 60, right: 10),
            dstX: 0, dstY: 0, dstW: 200, dstH: 200)
        XCTAssertEqual(tiles.count, 1, "非法 inset 应退化为单块")
        XCTAssertEqual(tiles[0].srcW, 100, accuracy: 1e-9)
        XCTAssertEqual(tiles[0].dstW, 200, accuracy: 1e-9)
    }

    func testZeroDestinationDegradesToSingleTile() {
        let tiles = computeNinePatchTiles(
            srcWidth: 100, srcHeight: 100,
            insets: NinePatchInsets(top: 10, left: 10, bottom: 10, right: 10),
            dstX: 0, dstY: 0, dstW: 0, dstH: 0)
        XCTAssertEqual(tiles.count, 1, "零目标应退化为单块")
    }

    // MARK: - parseAspectRatioToken

    func testParseValidRatioTokens() {
        XCTAssertEqual(parseAspectRatioToken("1x1")?.0, 1)
        XCTAssertEqual(parseAspectRatioToken("3x4")?.1, 4)
        XCTAssertEqual(parseAspectRatioToken("16x9")?.0, 16)
        XCTAssertEqual(parseAspectRatioToken("9x16")?.1, 16)
    }

    func testParseInvalidRatioTokens() {
        XCTAssertNil(parseAspectRatioToken(""))
        XCTAssertNil(parseAspectRatioToken("abc"))
        XCTAssertNil(parseAspectRatioToken("3"))
        XCTAssertNil(parseAspectRatioToken("3x"))
        XCTAssertNil(parseAspectRatioToken("0x4"))   // 0 不允许
        XCTAssertNil(parseAspectRatioToken("3x0"))
    }

    // MARK: - pickClosestAspectRatio

    func testPickClosestExactMatch() {
        let result = pickClosestAspectRatio(targetRatio: 0.75, candidates: ["1x1", "3x4", "9x16"])
        XCTAssertEqual(result, "3x4")  // 3/4 = 0.75 精确匹配
    }

    func testPickClosestApproximateMatch() {
        // targetRatio = 0.8（介于 3x4=0.75 和 1x1=1.0 之间，更接近 0.75）
        let result = pickClosestAspectRatio(targetRatio: 0.8, candidates: ["1x1", "3x4"])
        XCTAssertEqual(result, "3x4")  // |0.8-0.75|=0.05 < |0.8-1.0|=0.2
    }

    func testPickClosestEmptyCandidatesReturnsNil() {
        XCTAssertNil(pickClosestAspectRatio(targetRatio: 1.0, candidates: []))
    }

    func testPickClosestSkipsInvalidTokens() {
        // 候选含非法 token，应跳过
        let result = pickClosestAspectRatio(targetRatio: 1.0, candidates: ["abc", "1x1"])
        XCTAssertEqual(result, "1x1")
    }

    // MARK: - computeRatioSetAspectFillGeometry

    func testAspectFillEqualRatios() {
        // 素材 3:4 (0.75)，画布 300x400 (0.75) -> 完全贴合
        let geo = computeRatioSetAspectFillGeometry(assetAspectRatio: 0.75, canvasWidth: 300, canvasHeight: 400)
        XCTAssertEqual(geo.x, 0, accuracy: 1e-9)
        XCTAssertEqual(geo.y, 0, accuracy: 1e-9)
        XCTAssertEqual(geo.width, 300, accuracy: 1e-9)
        XCTAssertEqual(geo.height, 400, accuracy: 1e-9)
    }

    func testAspectFillWiderCanvasCropsVertically() {
        // 素材 3:4 (0.75)，画布 400x400 (1.0，比相框更宽) -> 宽铺满 400，高放大到 533.33，垂直居中 y = -66.66
        let geo = computeRatioSetAspectFillGeometry(assetAspectRatio: 0.75, canvasWidth: 400, canvasHeight: 400)
        XCTAssertEqual(geo.x, 0, accuracy: 1e-9)
        XCTAssertEqual(geo.width, 400, accuracy: 1e-9)
        XCTAssertEqual(geo.height, 400.0 / 0.75, accuracy: 1e-6)
        XCTAssertEqual(geo.y, (400.0 - 400.0 / 0.75) / 2.0, accuracy: 1e-6)
    }

    func testAspectFillNarrowerCanvasCropsHorizontally() {
        // 素材 1:1 (1.0)，画布 300x400 (0.75，比相框更窄) -> 高铺满 400，宽放大到 400，水平居中 x = -50
        let geo = computeRatioSetAspectFillGeometry(assetAspectRatio: 1.0, canvasWidth: 300, canvasHeight: 400)
        XCTAssertEqual(geo.y, 0, accuracy: 1e-9)
        XCTAssertEqual(geo.height, 400, accuracy: 1e-9)
        XCTAssertEqual(geo.width, 400, accuracy: 1e-9)
        XCTAssertEqual(geo.x, -50, accuracy: 1e-9)
    }

    func testAspectFillInvalidInputsFallback() {
        let geo = computeRatioSetAspectFillGeometry(assetAspectRatio: 0, canvasWidth: 100, canvasHeight: 100)
        XCTAssertEqual(geo.width, 100)
        XCTAssertEqual(geo.height, 100)
    }
}

