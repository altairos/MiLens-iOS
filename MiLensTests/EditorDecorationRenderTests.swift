//  EditorDecorationRenderTests —— 相框/贴纸 App 渲染级测试（Frame-Sticker-Development-Plan §9.2）。
//  用 CoreImageEditorProcessing 真实实现（非 mock）直接断导出像素，覆盖规格：
//  ① stretch / ninePatch / ratioSet 三种 fitMode 导出成功且绘制正确（预览与导出共用
//     resolveDecorationResource 选图 + orderedRenderLayers 排序，导出像素即共同基准）
//  ② 透明贴纸 PNG / JPEG 边缘无黑边白边（alpha=0 区域透出底图，premultiply 正确）
//  ③ 必需素材缺失（provider 返回 nil）→ 整体导出 nil，不产出缺层成功品（§7.4 渲染兜底）
//  ④ 连续拖/缩/旋一条撤销、⑤ Pro 门禁在 EditorViewModelTests（VM 决策级）；
//  ⑥ 保存回写「作品」分类在 MediaLifecycleServiceTests（service 事务级）。
//  采样均为对称点（中心/四角），对 CG 位图行序方向不敏感；素材用 scale=1 renderer 构造。
//  注意：未在本地执行（Windows 环境无法跑 App target XCTest），待 Mac/CI 验证。

import ImageIO
import MiLensKit
import UIKit
import XCTest
@testable import MiLens

final class EditorDecorationRenderTests: XCTestCase {

    private let processor = CoreImageEditorProcessing()

    // MARK: - ① fitMode 渲染基准

    /// stretch：单块拉伸铺满——红色素材叠加白底导出后画布中心为红。
    func testStretchFrameExportCoversCanvas() throws {
        let base = try makeColorImage(side: 60, color: .white)
        let frame = EditorLayer(
            id: "frame_1", type: .frame, zIndex: 1,
            x: 30, y: 30, width: 60, height: 60, resourcePath: "frame_stretch"
        )
        let source = DecorationRenderSource(image: try makeColorImage(side: 8, color: .red), fitMode: .stretch, ninePatchInsets: nil)

        let data = processor.renderExport(
            baseImage: base, layers: [photoLayer(side: 60), frame],
            canvasSize: CGSize(width: 60, height: 60),
            format: resolveSaveFormat(hasAlpha: false),
            decorationProvider: { $0 == "frame_stretch" ? source : nil }
        )

        let image = try decodeImage(try XCTUnwrap(data))
        let center = pixelRGBA(image, x: 30, y: 30)
        assertColor(center, expected: .red, tolerance: 8, "stretch 相框应覆盖画布中心")
    }

    /// ninePatch：四角不拉伸保形、中央窗口拉伸——角为素材角色、中心为素材中心色。
    func testNinePatchFrameExportKeepsCorners() throws {
        let base = try makeColorImage(side: 60, color: .white)
        let frame = EditorLayer(
            id: "frame_np", type: .frame, zIndex: 1,
            x: 30, y: 30, width: 60, height: 60, resourcePath: "frame_np"
        )
        let source = DecorationRenderSource(
            image: try makeNinePatchImage().cgImage ?? makeColorImage(side: 30, color: .green),
            fitMode: .ninePatch,
            ninePatchInsets: NinePatchInsets(top: 10, left: 10, bottom: 10, right: 10)
        )

        let data = processor.renderExport(
            baseImage: base, layers: [photoLayer(side: 60), frame],
            canvasSize: CGSize(width: 60, height: 60),
            format: resolveSaveFormat(hasAlpha: false),
            decorationProvider: { $0 == "frame_np" ? source : nil }
        )

        let image = try decodeImage(try XCTUnwrap(data))
        // 四角（角块 10×10 保形区）与中心（中央窗口）——对称采样规避行序方向歧义
        for (x, y) in [(5, 5), (54, 5), (5, 54), (54, 54)] {
            assertColor(pixelRGBA(image, x: x, y: y), expected: .red, tolerance: 8,
                        "九宫格角块 (\(x),\(y)) 应保持素材角色不变形")
        }
        assertColor(pixelRGBA(image, x: 30, y: 30), expected: .blue, tolerance: 8,
                    "九宫格中央窗口应铺素材中心色")
    }

    /// ratioSet：选图 token 由 resolveDecorationResource 按 targetRatio 解出（预览/导出同函数），
    /// provider 按解析名命中素材 → 导出成功且绘制正确。
    func testRatioSetAssetResolutionMatchesExportDraw() throws {
        let item = DecorationItem(
            id: "frame_ratio", name: "比例相框", category: .frame,
            resourcePath: "frame_ratio", previewPath: "frame_ratio",
            fitMode: .ratioSet, supportedRatios: ["1x1", "4x3"]
        )
        // 4:3 画布 → 选 4x3 素材（预览与导出共用同一解析，§9.2 ① 基准一致）
        XCTAssertEqual(resolveDecorationResource(item: item, targetRatio: 4.0 / 3.0), "frame_ratio_4x3")
        XCTAssertEqual(resolveDecorationResource(item: item, targetRatio: 1.0), "frame_ratio_1x1")

        let base = try makeColorImage(side: 60, color: .white)
        let frame = EditorLayer(
            id: "frame_r", type: .frame, zIndex: 1,
            x: 30, y: 30, width: 60, height: 60, resourcePath: "frame_ratio_4x3"
        )
        let source = DecorationRenderSource(image: try makeColorImage(side: 60, color: .blue), fitMode: .ratioSet, ninePatchInsets: nil)

        let data = processor.renderExport(
            baseImage: base, layers: [photoLayer(side: 60), frame],
            canvasSize: CGSize(width: 60, height: 60),
            format: resolveSaveFormat(hasAlpha: false),
            decorationProvider: { $0 == "frame_ratio_4x3" ? source : nil }
        )

        let image = try decodeImage(try XCTUnwrap(data))
        assertColor(pixelRGBA(image, x: 30, y: 30), expected: .blue, tolerance: 8,
                    "ratioSet 选中的素材应绘制到画布")
    }

    /// 生产目录中的 12 个贴纸都必须同时可预览、可解码并能进入真实导出管线。
    /// 该测试使用 Bundle 中的 catalog 与 Asset Catalog，不用合成占位素材替代生产资源。
    func testProductionStickerPackRendersThroughExport() throws {
        let catalog = try loadProductionCatalog()
        let stickers = catalog.items(for: .sticker)
        XCTAssertEqual(stickers.count, 12)

        let base = try makeColorImage(side: 80, color: .white)
        for item in stickers {
            XCTAssertEqual(item.previewPath, item.resourcePath, "贴纸预览应复用同一 imageset：\(item.id)")
            let image = try XCTUnwrap(
                UIImage(named: item.resourcePath),
                "贴纸 Asset Catalog 缺失或无法解码：\(item.resourcePath)"
            )
            let source = DecorationRenderSource(
                image: try XCTUnwrap(image.cgImage),
                fitMode: item.fitMode,
                ninePatchInsets: item.ninePatchInsets
            )
            let layer = EditorLayer(
                id: item.id, type: .sticker, zIndex: 2,
                x: 40, y: 40, width: 40, height: 40,
                resourcePath: item.resourcePath
            )
            let data = processor.renderExport(
                baseImage: base,
                layers: [photoLayer(side: 80), layer],
                canvasSize: CGSize(width: 80, height: 80),
                format: resolveSaveFormat(hasAlpha: true),
                decorationProvider: { $0 == item.resourcePath ? source : nil }
            )
            XCTAssertNotNil(data, "生产贴纸导出失败：\(item.id)")
        }
    }

    // MARK: - ② 透明贴纸边缘

    /// PNG：贴纸 alpha=0 区域透出白底图——无黑边（premultiply 错误会在透明区露黑）。
    func testTransparentStickerPNGKeepsCleanEdges() throws {
        let base = try makeColorImage(side: 40, color: .white)
        let sticker = EditorLayer(
            id: "sticker_1", type: .sticker, zIndex: 2,
            x: 20, y: 20, width: 20, height: 20, resourcePath: "sticker_alpha"
        )
        let source = DecorationRenderSource(
            image: try makeAlphaStickerImage().cgImage ?? makeColorImage(side: 20, color: .red),
            fitMode: .stretch,
            ninePatchInsets: nil
        )

        let data = processor.renderExport(
            baseImage: base, layers: [photoLayer(side: 40), sticker],
            canvasSize: CGSize(width: 40, height: 40),
            format: resolveSaveFormat(hasAlpha: true),
            decorationProvider: { $0 == "sticker_alpha" ? source : nil }
        )

        let image = try decodeImage(try XCTUnwrap(data))
        assertColor(pixelRGBA(image, x: 20, y: 20), expected: .red, tolerance: 8, "贴纸中心不透明区应为红")
        // 贴纸覆盖画布 10..30：透明区采样（贴纸内 alpha=0）与画布裸露角均应透出白底
        for (x, y) in [(12, 12), (27, 12), (12, 27), (27, 27)] {
            assertColor(pixelRGBA(image, x: x, y: y), expected: .white, tolerance: 8,
                        "透明区 (\(x),\(y)) 应透出底图（无黑边/白边 artifacts）")
        }
    }

    /// JPEG：透明贴纸 flatten 后透明区仍为底图白——不因 alpha 合成产生暗边。
    func testTransparentStickerJPEGFlattensWithoutDarkEdges() throws {
        let base = try makeColorImage(side: 40, color: .white)
        let sticker = EditorLayer(
            id: "sticker_1", type: .sticker, zIndex: 2,
            x: 20, y: 20, width: 20, height: 20, resourcePath: "sticker_alpha"
        )
        let source = DecorationRenderSource(
            image: try makeAlphaStickerImage().cgImage ?? makeColorImage(side: 20, color: .red),
            fitMode: .stretch,
            ninePatchInsets: nil
        )

        let data = processor.renderExport(
            baseImage: base, layers: [photoLayer(side: 40), sticker],
            canvasSize: CGSize(width: 40, height: 40),
            format: resolveSaveFormat(hasAlpha: false),
            decorationProvider: { $0 == "sticker_alpha" ? source : nil }
        )

        // JPEG 有损：容差放宽（4:2:0 色度抽样）
        let image = try decodeImage(try XCTUnwrap(data))
        assertColor(pixelRGBA(image, x: 20, y: 20), expected: .red, tolerance: 70, "贴纸中心应保持红")
        for (x, y) in [(12, 12), (27, 12), (12, 27), (27, 27)] {
            assertColor(pixelRGBA(image, x: x, y: y), expected: .white, tolerance: 30,
                        "flatten 后透明区 (\(x),\(y)) 应为底图白（无暗边）")
        }
    }

    // MARK: - ③ 素材缺失兜底

    /// 必需素材缺失（provider 返回 nil）：整体导出 nil，不产出缺层「成功品」（§7.4 渲染兜底；
    /// VM 预检路径见 EditorViewModelTests.testSaveAbortsWhenDecorationAssetMissing）。
    func testMissingDecorationAssetFailsWholeExport() throws {
        let base = try makeColorImage(side: 40, color: .white)
        let frame = EditorLayer(
            id: "frame_missing", type: .frame, zIndex: 1,
            x: 20, y: 20, width: 40, height: 40, resourcePath: "frame_missing"
        )

        let data = processor.renderExport(
            baseImage: base, layers: [photoLayer(side: 40), frame],
            canvasSize: CGSize(width: 40, height: 40),
            format: resolveSaveFormat(hasAlpha: false),
            decorationProvider: { _ in nil }
        )

        XCTAssertNil(data, "素材缺失必须整体失败（缺一档 → 缺整档，§7.2）")
    }

    // MARK: - 测试素材辅助（scale=1，像素坐标即 pt 坐标）

    /// 照片底层（renderExport 底图单独绘制，photo 层仅参与翻转判定）。
    private func photoLayer(side: Double) -> EditorLayer {
        EditorLayer(id: "photo_1", type: .photo, zIndex: 0, x: side / 2, y: side / 2,
                    width: side, height: side)
    }

    private func loadProductionCatalog() throws -> DecorationCatalog {
        let url = Bundle.main.url(
            forResource: "catalog", withExtension: "json", subdirectory: "Decorations"
        ) ?? Bundle.main.url(forResource: "catalog", withExtension: "json")
        let data = try XCTUnwrap(url.flatMap { try? Data(contentsOf: $0) }, "生产 catalog 不在测试 Bundle")
        return try JSONDecoder().decode(DecorationCatalog.self, from: data)
    }

    /// 纯色方图（scale=1：cgImage 像素 = side×side）。
    private func makeColorImage(side: CGFloat, color: UIColor) throws -> CGImage {
        let ui = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: scaleOneFormat()
        ).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        return try XCTUnwrap(ui.cgImage, "纯色素材 cgImage 不应为 nil")
    }

    /// 九宫格素材 30×30（insets 10）：四角红 / 边绿 / 中央蓝。
    private func makeNinePatchImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30), format: scaleOneFormat())
            .image { ctx in
                UIColor.green.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
                UIColor.blue.setFill()
                ctx.fill(CGRect(x: 10, y: 10, width: 10, height: 10))
                UIColor.red.setFill()
                for rect in [CGRect(x: 0, y: 0, width: 10, height: 10),
                             CGRect(x: 20, y: 0, width: 10, height: 10),
                             CGRect(x: 0, y: 20, width: 10, height: 10),
                             CGRect(x: 20, y: 20, width: 10, height: 10)] {
                    ctx.fill(rect)
                }
            }
    }

    /// 透明贴纸素材 20×20：中心 8×8 不透明红，其余 alpha=0。
    private func makeAlphaStickerImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: scaleOneFormat())
            .image { ctx in
                UIColor.red.setFill()
                ctx.fill(CGRect(x: 6, y: 6, width: 8, height: 8))
            }
    }

    /// scale=1 + 透明画布（cgImage 像素与 pt 一致，alpha 可用）。
    private func scaleOneFormat() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return format
    }

    /// 解码导出数据为 CGImage。
    private func decodeImage(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// 读单像素 RGBA（x/y 为从图像左上角起的列/行；1×1 位图上下文偏移采样，无插值）。
    private func pixelRGBA(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            ctx.interpolationQuality = .none
            // CG 坐标 y 向上：第 y 行（顶部起）对应 CG y = height-1-y，平移使该像素落在 (0,0)
            ctx.draw(image, in: CGRect(
                x: CGFloat(-x), y: CGFloat(-(image.height - 1 - y)),
                width: CGFloat(image.width), height: CGFloat(image.height)
            ))
        }
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    /// 像素颜色断言（容差按通道；JPEG 用宽容差，PNG 用窄容差）。
    private func assertColor(
        _ pixel: (UInt8, UInt8, UInt8, UInt8), expected: UIColor,
        tolerance: UInt8, _ message: @autoclosure () -> String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        expected.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let er = UInt8(red * 255), eg = UInt8(green * 255), eb = UInt8(blue * 255)
        let diffs = (
            abs(Int(pixel.0) - Int(er)), abs(Int(pixel.1) - Int(eg)), abs(Int(pixel.2) - Int(eb))
        )
        XCTAssertLessThanOrEqual(
            max(diffs.0, diffs.1, diffs.2), Int(tolerance),
            "\(message())：got rgba(\(pixel.0),\(pixel.1),\(pixel.2),\(pixel.3)) " +
            "expected rgb(\(er),\(eg),\(eb))±\(tolerance)",
            file: file, line: line
        )
    }
}
