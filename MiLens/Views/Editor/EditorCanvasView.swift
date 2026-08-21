//  EditorCanvasView —— 编辑器画布（对应源端 editor/EditorCanvasSurface.ets + EditorCropController.draw）。
//  显示：底图（含翻转属性）+ 文字图层 + 选中框（LayerGeometry）+ 裁剪覆盖层（EditorCropOverlay 驱动）。
//  手势：裁剪模式拖动裁剪框；常规模式点选/拖动/缩放/旋转活动图层（手势合并为一条历史）。
//  坐标系统：画布 = 图片 fit 显示区域（ViewModel.canvasSize），图层 x/y 为画布中心点坐标。

import SwiftUI
import MiLensKit
import UIKit

struct EditorCanvasView: View {
    @Bindable var viewModel: EditorViewModel

    /// 裁剪手势起点（onChanged 时用起点 + translation 计算新位置）。
    @State private var cropDragStart: EditorCropRect?

    /// 图层拖动上次累计位移（DragGesture.translation 是相对手势起点的累计值，
    /// moveActiveLayer 为增量语义：差值传入，否则重复累加导致图层超速漂移）。
    @State private var layerDragLast: CGSize = .zero

    /// 当前图层手势是否已经完成首次命中。每次手势都先按触点重新命中，
    /// 这样可以在多张贴纸之间切换选中，也可以点空白处清除选中。
    @State private var layerGestureHasSelected = false

    var body: some View {
        GeometryReader { geo in
            let canvasRect = Self.fitRect(container: geo.size, aspectRatio: viewModel.photoAspectRatio)
            ZStack {
                Color.milensSealSurface.ignoresSafeArea()

                ZStack {
                    baseImageView
                    decorationLayers
                    textLayers
                    selectionBoxView(canvasRect: canvasRect)
                    snapGuideLines(canvasRect: canvasRect)
                    if viewModel.tool == .crop {
                        cropOverlayView(canvasRect: canvasRect)
                    }
                }
                .frame(width: canvasRect.width, height: canvasRect.height)
                .contentShape(Rectangle())
                .gesture(canvasGesture())
            }
            .onAppear {
                viewModel.setCanvasSize(canvasRect.size)
            }
            .onChange(of: canvasRect.size) { _, newSize in
                viewModel.setCanvasSize(newSize)
            }
        }
    }

    // MARK: - 底图

    private var baseImageView: some View {
        Group {
            if let image = viewModel.photoImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaleEffect(x: viewModel.photoFlipX ? -1 : 1, y: viewModel.photoFlipY ? -1 : 1)
            } else {
                Rectangle()
                    .fill(Color.milensSealSurface.opacity(0.5))
                    .overlay(ProgressView().tint(.white))
            }
        }
    }

    // MARK: - 文字图层

    @ViewBuilder
    private var textLayers: some View {
        ForEach(orderedRenderLayers(viewModel.layers)) { layer in
            if layer.type == .text && layer.visible {
                Text(layer.text)
                    .font(.system(size: layer.fontSize))
                    .foregroundStyle(Color(hexString: layer.fontColor) ?? .white)
                    // V1.0 描边简化为同色阴影（源端 Canvas stroke 绘制）
                    .shadow(color: Color(hexString: layer.strokeColor) ?? .black,
                            radius: layer.strokeWidth)
                    .scaleEffect(layer.scale)
                    .rotationEffect(.degrees(layer.rotation))
                    .position(x: layer.x, y: layer.y)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 装饰图层（相框 / 贴纸）

    /// 画布预览渲染已添加的相框 / 贴纸图层（阻塞项4）：
    /// - 素材名经 viewModel.resolveDecorationSource 解析（ratioSet 按画布比例选图，与导出一致）；
    /// - fitMode 三模式预览：stretch 拉伸 / ninePatch 分块（computeNinePatchTiles，与导出同源）/ ratioSet 已选图后单图拉伸；
    /// - 命中：贴纸参与点选/手势（命中判定在 selectLayer）；相框铺满画布保持不可命中。
    @ViewBuilder
    private var decorationLayers: some View {
        // 预览必须与导出共用稳定合成顺序：photo → frame → sticker → text。
        // 否则先加贴纸、后加相框时，相框会错误地盖在贴纸上。
        ForEach(orderedRenderLayers(viewModel.layers)) { layer in
            if (layer.type == .frame || layer.type == .sticker) && layer.visible,
               let source = viewModel.resolveDecorationSource(for: layer) {
                DecorationLayerView(layer: layer, source: source)
                    .allowsHitTesting(layer.type == .sticker)
            }
        }
    }

    // MARK: - 选中框（虚线 + 角手柄）

    @ViewBuilder
    private func selectionBoxView(canvasRect: CGRect) -> some View {
        if let activeID = viewModel.activeLayerID,
           let active = viewModel.layers.first(where: { $0.id == activeID }),
           active.type != .photo {
            let geo = computeSelectionBoxGeometry(active)
            ZStack {
                Rectangle()
                    .strokeBorder(Color.milensActionPrimary,
                                  style: StrokeStyle(lineWidth: geo.lineWidth,
                                                     dash: geo.dashPattern.map { CGFloat($0) }))
                    .frame(width: geo.halfW * 2, height: geo.halfH * 2)
                ForEach(0..<4, id: \.self) { i in
                    let corner = geo.corners[i]
                    Circle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: geo.handleSize * 2, height: geo.handleSize * 2)
                        .position(x: corner[0], y: corner[1])
                }
            }
            .rotationEffect(.degrees(active.rotation))
            .position(x: active.x, y: active.y)
            .allowsHitTesting(false)
        }
    }

    // MARK: - 拖动吸附中心参考线（M2 质量项，规格 §4.3）

    /// 拖动中吸附对齐时显示画布水平/垂直中心参考线（铜色虚线，与选中框同色系）。
    /// 出现/消失为瞬时切换，不附加动画（Reduce Motion 天然满足；吸附无回弹）。
    @ViewBuilder
    private func snapGuideLines(canvasRect: CGRect) -> some View {
        if viewModel.showsSnapGuideX || viewModel.showsSnapGuideY {
            Path { path in
                if viewModel.showsSnapGuideX {
                    path.move(to: CGPoint(x: canvasRect.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: canvasRect.width / 2, y: canvasRect.height))
                }
                if viewModel.showsSnapGuideY {
                    path.move(to: CGPoint(x: 0, y: canvasRect.height / 2))
                    path.addLine(to: CGPoint(x: canvasRect.width, y: canvasRect.height / 2))
                }
            }
            .stroke(Color.milensActionPrimary.opacity(0.8),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .allowsHitTesting(false)
        }
    }

    // MARK: - 裁剪覆盖层（遮罩/边框/九宫格/角标）

    @ViewBuilder
    private func cropOverlayView(canvasRect: CGRect) -> some View {
        if let cropRect = viewModel.cropVM.cropRect {
            let mask = computeCropOverlayMask(
                canvasW: canvasRect.width, canvasH: canvasRect.height, rect: cropRect
            )
            ZStack {
                // 遮罩（四块半透明黑）
                ForEach(Array([mask.top, mask.bottom, mask.left, mask.right].enumerated()), id: \.offset) { _, rect in
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: rect.w, height: rect.h)
                        .position(x: rect.x + rect.w / 2, y: rect.y + rect.h / 2)
                }
                // 裁剪框边框
                Rectangle()
                    .strokeBorder(.white, lineWidth: CROP_BORDER_WIDTH)
                    .frame(width: cropRect.w, height: cropRect.h)
                    .position(x: cropRect.x + cropRect.w / 2, y: cropRect.y + cropRect.h / 2)
                // 九宫格辅助线
                Path { path in
                    let thirds = computeCropThirdsLines(rect: cropRect)
                    for xLine in thirds.xLines {
                        path.move(to: CGPoint(x: xLine, y: cropRect.y))
                        path.addLine(to: CGPoint(x: xLine, y: cropRect.y + cropRect.h))
                    }
                    for yLine in thirds.yLines {
                        path.move(to: CGPoint(x: cropRect.x, y: yLine))
                        path.addLine(to: CGPoint(x: cropRect.x + cropRect.w, y: yLine))
                    }
                }
                .stroke(.white.opacity(0.3), lineWidth: CROP_GRID_WIDTH)
                // 角标（四角 L 形，珊瑚色，对照 Figma Corner H/V fill_225c8549）
                Path { path in
                    for handle in computeCropCornerHandles(rect: cropRect) {
                        path.move(to: CGPoint(x: handle.x, y: handle.y))
                        path.addLine(to: CGPoint(x: handle.x + CROP_HANDLE_LENGTH * Double(handle.dx), y: handle.y))
                        path.move(to: CGPoint(x: handle.x, y: handle.y))
                        path.addLine(to: CGPoint(x: handle.x, y: handle.y + CROP_HANDLE_LENGTH * Double(handle.dy)))
                    }
                }
                .stroke(Color.milensActionPrimary, lineWidth: CROP_HANDLE_WIDTH)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - 手势

    /// 画布手势：裁剪模式拖动裁剪框；常规模式点选/拖动/缩放/旋转活动图层（手势合并为一条历史）。
    /// 缩放/旋转仅在无工具激活时生效（避免裁剪模式误改活动图层）。
    private func canvasGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if viewModel.tool == .crop {
                    cropDragChanged(value)
                } else {
                    layerTapOrDragChanged(value)
                }
            }
            .onEnded { _ in
                if viewModel.tool == .crop {
                    cropDragStart = nil
                    layerGestureHasSelected = false
                } else {
                    layerDragLast = .zero
                    layerGestureHasSelected = false
                    viewModel.endLayerGesture()
                }
            }
            .simultaneously(with: MagnifyGesture()
                .onChanged { value in
                    guard viewModel.tool == .none else { return }
                    viewModel.beginLayerGesture()
                    viewModel.scaleActiveLayer(by: value.magnification)
                }
                .onEnded { _ in
                    if viewModel.tool == .none { viewModel.endLayerGesture() }
                })
            .simultaneously(with: RotationGesture()
                .onChanged { value in
                    guard viewModel.tool == .none else { return }
                    viewModel.beginLayerGesture()
                    viewModel.rotateActiveLayer(by: value.degrees)
                }
                .onEnded { _ in
                    if viewModel.tool == .none { viewModel.endLayerGesture() }
                })
    }

    /// 裁剪框拖动（起点 + translation，源端 cropCtrl.pan 语义）。
    private func cropDragChanged(_ value: DragGesture.Value) {
        let start = cropDragStart ?? viewModel.cropVM.cropRect ?? EditorCropRect(x: 0, y: 0, w: 0, h: 0)
        cropDragStart = start
        viewModel.cropVM.updateCropRect(EditorCropRect(
            x: start.x + value.translation.width,
            y: start.y + value.translation.height,
            w: start.w, h: start.h
        ))
    }

    /// 常规模式：每次手势先按触点命中图层，再拖动命中的活动图层。
    /// DragGesture 附着在画布内部 ZStack，location 已经是画布本地坐标，
    /// 不应再次减去外层 GeometryReader 的 canvasRect 原点。
    /// translation 为相对手势起点的累计值，取差值作为增量传给 moveActiveLayer。
    private func layerTapOrDragChanged(_ value: DragGesture.Value) {
        if !layerGestureHasSelected {
            layerGestureHasSelected = true
            viewModel.selectLayer(at: value.location)
        }
        if viewModel.activeLayerID != nil {
            viewModel.beginLayerGesture()
            let dx = value.translation.width - layerDragLast.width
            let dy = value.translation.height - layerDragLast.height
            layerDragLast = value.translation
            viewModel.moveActiveLayer(dx: Double(dx), dy: Double(dy))
        }
    }

    // MARK: - 布局辅助

    /// 图片 fit 显示区域（保持 photoAspectRatio，居中）。
    static func fitRect(container: CGSize, aspectRatio: Double) -> CGRect {
        guard container.width > 0, container.height > 0, aspectRatio > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let ratio = CGFloat(aspectRatio)
        if container.width / container.height > ratio {
            let h = container.height
            let w = h * ratio
            return CGRect(x: (container.width - w) / 2, y: 0, width: w, height: h)
        } else {
            let w = container.width
            let h = w / ratio
            return CGRect(x: 0, y: (container.height - h) / 2, width: w, height: h)
        }
    }
}

/// 预览侧装饰素材解析结果（EditorViewModel.resolveDecorationSource 产出）。
/// assetName 已按画布比例经 resolveDecorationResource 选好（ratioSet 选图与导出一致）。
struct DecorationPreviewSource {
    /// 实际加载的 Asset Catalog imageset 名。
    let assetName: String
    /// 相框自适应模式（来自 DecorationItem.fitMode；sticker 恒 stretch）。
    let fitMode: FrameFitMode
    /// 九宫格切图内边距（仅 ninePatch 时非 nil，源图像素空间）。
    let ninePatchInsets: NinePatchInsets?
}

/// 装饰图片解码缓存：NSCache（内存警告自动回收）+ 后台解码（参照 ThumbnailCache 模式，
/// 阻塞项4：UIImage(named:) 的磁盘读取/解码移出 body）。
/// 解码失败记录素材名（开发计划 §7.2 素材错误诊断），面板单元据此显示不可用状态。
@MainActor
enum DecorationImageLoader {
    private static let cache = NSCache<NSString, UIImage>()
    /// 已知解码失败的素材名（§7.2：记录素材 ID；记录/查询均在主线程）。
    private static var failedNames: Set<String> = []

    /// 取图：缓存命中直接返回；否则后台读取+解码后回填。
    static func load(_ name: String) async -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(named: name)
        }.value
        if let image {
            cache.setObject(image, forKey: name as NSString)
            failedNames.remove(name) // 重试成功（如内存回收后再加载）解除不可用
        } else {
            failedNames.insert(name)
        }
        return image
    }

    /// 素材是否已知解码失败（面板不可用状态判定；导出预检走 VM 的同步预解码路径）。
    static func hasFailed(_ name: String) -> Bool {
        failedNames.contains(name)
    }
}

/// 装饰图层预览子视图（相框 / 贴纸）。
///
/// - stretch / ratioSet：单图拉伸（ratioSet 的选图已由 source.assetName 完成）。
/// - ninePatch：Canvas 内 computeNinePatchTiles 分 9 块绘制（与导出同源纯函数）。
/// 图片经 DecorationImageLoader 异步解码，未加载完成时不占位（加载后淡入）。
private struct DecorationLayerView: View {
    let layer: EditorLayer
    let source: DecorationPreviewSource

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let img = uiImage {
                if source.fitMode == .ninePatch, let insets = source.ninePatchInsets {
                    ninePatchCanvas(img, insets: insets)
                } else {
                    Image(uiImage: img).resizable()
                }
            }
        }
        .opacity(layer.opacity)
        // layer.width/height/scale 为 Double，.frame 需 CGFloat（显式转换避免类型错误）。
        .frame(width: CGFloat(layer.width * layer.scale),
               height: CGFloat(layer.height * layer.scale))
        .rotationEffect(.degrees(layer.rotation))
        .scaleEffect(x: layer.flipX ? -1 : 1, y: layer.flipY ? -1 : 1)
        .position(x: layer.x, y: layer.y)
        .task(id: source.assetName) {
            uiImage = await DecorationImageLoader.load(source.assetName)
        }
    }

    /// 九宫格分块预览（Canvas 左上原点；目标矩形 = 图层显示区；源矩形用像素坐标，
    /// 与导出 CGImage.cropping 一致）。
    private func ninePatchCanvas(_ img: UIImage, insets: NinePatchInsets) -> some View {
        Canvas { context, size in
            let srcW = Double(img.cgImage?.width ?? 0)
            let srcH = Double(img.cgImage?.height ?? 0)
            guard srcW > 0, srcH > 0 else { return }
            let tiles = computeNinePatchTiles(
                srcWidth: srcW, srcHeight: srcH,
                insets: insets,
                dstX: 0, dstY: 0,
                dstW: Double(size.width), dstH: Double(size.height))
            // draw(_:in:slice:) 为 iOS 18 API 且 slice 用单位坐标；iOS 17 改用
            // CGImage.cropping 取像素子图绘制，与导出路径（CGImage.cropping）一致。
            for tile in tiles {
                guard tile.srcW > 0, tile.srcH > 0, tile.dstW > 0, tile.dstH > 0 else { continue }
                guard let cg = img.cgImage?.cropping(to: CGRect(
                    x: tile.srcX, y: tile.srcY, width: tile.srcW, height: tile.srcH)) else { continue }
                context.draw(
                    Image(decorative: cg, scale: img.scale),
                    in: CGRect(x: tile.dstX, y: tile.dstY, width: tile.dstW, height: tile.dstH)
                )
            }
        }
    }
}

extension Color {
    /// 解析 "#RRGGBB" 十六进制颜色（编辑器文字/选中框颜色；解析失败返回 nil）。
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
