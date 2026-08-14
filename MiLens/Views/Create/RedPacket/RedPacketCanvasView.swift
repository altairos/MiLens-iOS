//  RedPacketCanvasView —— 红包画布（对应红包封面开发计划 §3.2）。
//
//  GeometryReader fit 957×1278 比例；嵌入 RedPacketCoverRenderer（安全区遮罩开）。
//  手势：单指拖动移动活动层、双指缩放旋转、点击空白 deselect、选中框。

import SwiftUI
import MiLensKit

struct RedPacketCanvasView: View {
    @Bindable var viewModel: RedPacketWorkshopViewModel

    @State private var lastDragTranslation: CGSize = .zero
    @State private var lastScale: Double = 1.0
    @State private var lastRotation: Double = 0

    var body: some View {
        GeometryReader { geo in
            let canvasRect = Self.fitRect(container: geo.size)
            ZStack {
                Color.milensSealSurface

                ZStack {
                    RedPacketCoverRenderer(
                        template: viewModel.template,
                        layers: viewModel.layers,
                        petImage: viewModel.cutoutImage,
                        includeWatermark: !viewModel.isPro,
                        showSafeZone: true
                    )

                    // 选中框
                    if let activeID = viewModel.activeLayerID,
                       let active = viewModel.layers.first(where: { $0.id == activeID }) {
                        selectionBox(active, canvasRect: canvasRect)
                    }
                }
                .frame(width: canvasRect.width, height: canvasRect.height)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .gesture(canvasTapGesture(canvasRect: canvasRect))
                .gesture(canvasDragGesture(canvasRect: canvasRect))
                .gesture(canvasMagnifyGesture())
                .gesture(canvasRotationGesture())
            }
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - 手势

    private func canvasTapGesture(canvasRect: CGRect) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                // 手势挂在内层 ZStack（即画布本体）上，location 已是画布本地坐标。
                let p = CGPoint(
                    x: value.location.x / canvasRect.width * rpCanvasWidth,
                    y: value.location.y / canvasRect.height * rpCanvasHeight
                )
                viewModel.selectLayer(at: p)
            }
    }

    private func canvasDragGesture(canvasRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                viewModel.beginGestureEdit()
                // 计算本次增量（相对上次 translation）
                let deltaW = value.translation.width - lastDragTranslation.width
                let deltaH = value.translation.height - lastDragTranslation.height
                lastDragTranslation = value.translation
                let dx = deltaW / canvasRect.width * rpCanvasWidth
                let dy = deltaH / canvasRect.height * rpCanvasHeight
                viewModel.moveActive(dx: Double(dx), dy: Double(dy))
            }
            .onEnded { _ in
                lastDragTranslation = .zero
                viewModel.endGestureEdit()
            }
    }

    private func canvasMagnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                viewModel.beginGestureEdit()
                let factor = Double(value.magnification / lastScale)
                viewModel.scaleActive(by: factor)
                lastScale = value.magnification
            }
            .onEnded { _ in
                lastScale = 1.0
                viewModel.endGestureEdit()
            }
    }

    private func canvasRotationGesture() -> some Gesture {
        RotateGesture()
            .onChanged { value in
                viewModel.beginGestureEdit()
                let delta = Double(value.rotation.degrees - lastRotation)
                viewModel.rotateActive(by: delta)
                lastRotation = value.rotation.degrees
            }
            .onEnded { _ in
                lastRotation = 0
                viewModel.endGestureEdit()
            }
    }

    // MARK: - 选中框

    private func selectionBox(_ layer: RedPacketLayer, canvasRect: CGRect) -> some View {
        let half = rpComputeLayerHalfSize(layer)
        let scaleX = canvasRect.width / rpCanvasWidth
        let scaleY = canvasRect.height / rpCanvasHeight
        let w = half.halfW * 2 * scaleX
        let h = half.halfH * 2 * scaleY
        return Rectangle()
            .stroke(Color.white.opacity(0.8), style: StrokeStyle(
                lineWidth: 1.5, dash: [4, 3]
            ))
            .frame(width: max(w, 20), height: max(h, 20))
            .rotationEffect(.degrees(layer.rotation))
            // 父 ZStack 即画布本体（原点 0,0），position 无需 canvasRect 偏移。
            .position(
                x: layer.x * scaleX,
                y: layer.y * scaleY
            )
            .allowsHitTesting(false)
    }

    // MARK: - 布局辅助

    /// 图片 fit 显示区域（保持 957×1278 比例，居中）。
    static func fitRect(container: CGSize) -> CGRect {
        let ratio = rpCanvasWidth / rpCanvasHeight
        guard container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
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
