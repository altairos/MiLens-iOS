//  EditorCanvasView —— 编辑器画布（对应源端 editor/EditorCanvasSurface.ets + EditorCropController.draw）。
//  显示：底图（含翻转属性）+ 文字图层 + 选中框（LayerGeometry）+ 裁剪覆盖层（EditorCropOverlay 驱动）。
//  手势：裁剪模式拖动裁剪框；常规模式点选/拖动/缩放/旋转活动图层（手势合并为一条历史）。
//  坐标系统：画布 = 图片 fit 显示区域（ViewModel.canvasSize），图层 x/y 为画布中心点坐标。

import SwiftUI
import MiLensKit

struct EditorCanvasView: View {
    @Bindable var viewModel: EditorViewModel

    /// 裁剪手势起点（onChanged 时用起点 + translation 计算新位置）。
    @State private var cropDragStart: EditorCropRect?

    var body: some View {
        GeometryReader { geo in
            let canvasRect = Self.fitRect(container: geo.size, aspectRatio: viewModel.photoAspectRatio)
            ZStack {
                Color.black.ignoresSafeArea()

                ZStack {
                    baseImageView
                    textLayers
                    selectionBoxView(canvasRect: canvasRect)
                    if viewModel.tool == .crop {
                        cropOverlayView(canvasRect: canvasRect)
                    }
                }
                .frame(width: canvasRect.width, height: canvasRect.height)
                .contentShape(Rectangle())
                .gesture(canvasGesture(canvasRect: canvasRect))
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
                    .fill(Color.black.opacity(0.3))
                    .overlay(ProgressView().tint(.white))
            }
        }
    }

    // MARK: - 文字图层

    @ViewBuilder
    private var textLayers: some View {
        ForEach(viewModel.layers) { layer in
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

    // MARK: - 选中框（虚线 + 角手柄）

    @ViewBuilder
    private func selectionBoxView(canvasRect: CGRect) -> some View {
        if let activeID = viewModel.activeLayerID,
           let active = viewModel.layers.first(where: { $0.id == activeID }),
           active.type != .photo {
            let geo = computeSelectionBoxGeometry(active)
            ZStack {
                Rectangle()
                    .strokeBorder(Color(hexString: DEFAULT_SELECTION_COLOR) ?? .blue,
                                  style: StrokeStyle(lineWidth: geo.lineWidth,
                                                     dash: geo.dashPattern.map { CGFloat($0) }))
                    .frame(width: geo.halfW * 2, height: geo.halfH * 2)
                ForEach(0..<4, id: \.self) { i in
                    let corner = geo.corners[i]
                    Circle()
                        .fill(Color(hexString: DEFAULT_SELECTION_COLOR) ?? .blue)
                        .frame(width: geo.handleSize * 2, height: geo.handleSize * 2)
                        .position(x: corner[0], y: corner[1])
                }
            }
            .rotationEffect(.degrees(active.rotation))
            .position(x: active.x, y: active.y)
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
                // 角标（四角 L 形）
                Path { path in
                    for handle in computeCropCornerHandles(rect: cropRect) {
                        path.move(to: CGPoint(x: handle.x, y: handle.y))
                        path.addLine(to: CGPoint(x: handle.x + CROP_HANDLE_LENGTH * Double(handle.dx), y: handle.y))
                        path.move(to: CGPoint(x: handle.x, y: handle.y))
                        path.addLine(to: CGPoint(x: handle.x, y: handle.y + CROP_HANDLE_LENGTH * Double(handle.dy)))
                    }
                }
                .stroke(.white, lineWidth: CROP_HANDLE_WIDTH)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - 手势

    /// 画布手势：裁剪模式拖动裁剪框；常规模式点选/拖动/缩放/旋转活动图层（手势合并为一条历史）。
    /// 缩放/旋转仅在无工具激活时生效（避免裁剪模式误改活动图层）。
    private func canvasGesture(canvasRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if viewModel.tool == .crop {
                    cropDragChanged(value)
                } else {
                    layerTapOrDragChanged(value, canvasRect: canvasRect)
                }
            }
            .onEnded { _ in
                if viewModel.tool == .crop {
                    cropDragStart = nil
                } else {
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

    /// 常规模式：无活动图层时点选（画布内坐标），有活动图层时拖动。
    private func layerTapOrDragChanged(_ value: DragGesture.Value, canvasRect: CGRect) {
        if viewModel.activeLayerID == nil {
            let p = CGPoint(
                x: value.location.x - canvasRect.minX,
                y: value.location.y - canvasRect.minY
            )
            viewModel.selectLayer(at: p)
        }
        if viewModel.activeLayerID != nil {
            viewModel.beginLayerGesture()
            viewModel.moveActiveLayer(dx: value.translation.width, dy: value.translation.height)
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
