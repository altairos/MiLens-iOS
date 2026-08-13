//  EditorAdjustPanelVM —— 调色工具子状态（M2 拆分，对应源端 EditorAdjustController）。
//  5 滑块（亮度/对比度/饱和度/色温/锐化）+ 重置；决策走 MiLensKit EditorAdjustLogic。
//  锐化基于未锐化底图卷积后叠加调色渲染（对齐源端 releaseSharpenBase 语义）。

import CoreGraphics
import Foundation
import MiLensKit
import Observation
import UIKit

@MainActor
@Observable
final class EditorAdjustPanelVM {

    private unowned let owner: EditorViewModel
    private let document: EditorDocumentController

    init(owner: EditorViewModel) {
        self.owner = owner
        self.document = owner.document
    }

    var state = EditorAdjustPanelState()
    /// 上次成功卷积后记录的锐化强度（resolveSharpnessApply 的 prev 基准；
    /// 对齐源端 releaseSharpenBase：撤销/重置后回到 0，不重复卷积）。
    var renderedSharpness = 0.0

    /// 当前高亮的预设滤镜 id（nil = 自定义，无高亮）。
    /// 由 syncFromLayer → matchPresetFilter 统一回填，是单一事实来源：
    /// applyPreset / 手动滑块 / reset / undo / redo 后都经 syncState 自动算出。
    var selectedFilterID: String?
    /// 手动调整滑块区是否展开（默认折叠，滤镜横滚条为主交互入口）。
    var isSlidersExpanded = false
    /// 预设滤镜缩略图缓存（key = "photoGeneration_presetId"）。
    private var filterThumbnailCache: [String: UIImage] = [:]

    func onSliderChange(_ field: EditorAdjustField, value: Double, phase: EditorSliderGesturePhase) {
        let gesture = resolveSliderGesture(phase)
        if gesture.shouldBeginGesture { document.beginGesture() }

        switch field {
        case .brightness: state.brightness = value
        case .contrast: state.contrast = value
        case .saturation: state.saturation = value
        case .temperature: state.temperature = value
        case .sharpness: state.sharpness = value
        }

        guard let layer = document.photoLayer() else { return }
        if field == .sharpness {
            // 锐化需要卷积：写回图层值，仅 end/click 且强度变化时渲染（源端异步卷积语义）。
            // prev 基准是「上次渲染的强度」而非图层值，否则 begin/moving 已写回后 end 永不触发。
            let decision = resolveSharpnessApply(
                prevStrength: renderedSharpness, nextStrength: value, phase: phase
            )
            document.updateLayer(layer.id) { $0.adjustments.sharpness = value }
            document.pushHistory()
            if decision.shouldApply {
                renderedSharpness = decision.strength
                owner.refreshPhotoImage()
            }
        } else {
            apply()
        }
        owner.syncState()

        if gesture.shouldEndGesture { document.endGesture() }
    }

    func reset() {
        guard !isAdjustNeutral(state) else { return }
        state = defaultAdjustPanelState()
        if let layer = document.photoLayer() {
            document.updateLayer(layer.id) { $0.adjustments = NEUTRAL_EDITOR_ADJUSTMENTS }
        }
        document.pushHistory()
        owner.refreshPhotoImage()
        owner.syncState()
    }

    // MARK: - 预设滤镜（iOS 端新增）

    /// 应用预设滤镜：一键写入预设调色参数。
    /// selectedFilterID 由 syncState → syncFromLayer → matchPresetFilter 统一回填，
    /// 这里不直接设值，保证手动微调后偏离预设 → 自动取消高亮。
    func applyPreset(_ preset: PresetFilter) {
        guard let layer = document.photoLayer() else { return }
        state = syncAdjustPanelState(preset.adjustments)
        let adj = buildAdjustments(state)
        document.updateLayer(layer.id) { $0.adjustments = adj }
        document.pushHistory()
        owner.refreshPhotoImage()
        owner.syncState()
    }

    /// 手动调整滑块区折叠 / 展开（默认折叠，滤镜横滚条为主交互入口）。
    func toggleSlidersExpanded() {
        isSlidersExpanded.toggle()
    }

    /// 预设滤镜缩略图：底图降采样后应用预设调色（仅调色，不含锐化卷积）。
    /// 按 photoGeneration 缓存；裁剪/旋转/抠图后底图变化自动失效重建。
    func filterThumbnail(for preset: PresetFilter) -> UIImage? {
        let key = "\(owner.photoGeneration)_\(preset.id)"
        if let cached = filterThumbnailCache[key] { return cached }
        guard let base = owner.baseImage else { return nil }
        let small = downsample(base, maxDimension: 120)
        let adjusted = owner.imageProcessor.applyingAdjustments(to: small, adjustments: preset.adjustments)
        let img = UIImage(cgImage: adjusted)
        filterThumbnailCache[key] = img
        return img
    }

    /// Core Graphics 降采样（高质量插值，控制缩略图内存，遵循 DESIGN.md §3 解码缓冲有上限）。
    private func downsample(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let scale = min(maxDimension / CGFloat(image.width), maxDimension / CGFloat(image.height), 1)
        guard scale < 1 else { return image }
        let w = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let h = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// 像素级操作（裁剪/旋转）后锐化归零（基准内容变化）。
    func resetSharpness() {
        state.sharpness = 0
    }

    /// 把面板状态写回照片图层并渲染（实时预览；手势内 push 自动合并）。
    private func apply() {
        guard let layer = document.photoLayer() else { return }
        let adj = buildAdjustments(state)
        document.updateLayer(layer.id) { $0.adjustments = adj }
        document.pushHistory()
        owner.refreshPhotoImage()
    }

    /// 从照片图层回读面板（进入调色工具 / undo / redo 后同步，源端 syncAdjustmentsFromPhoto）。
    /// 同时回填 selectedFilterID：当前参数精确等于某预设则高亮，否则 nil（自定义）。
    func syncFromLayer() {
        let adj = document.photoLayer()?.adjustments ?? NEUTRAL_EDITOR_ADJUSTMENTS
        state = syncAdjustPanelState(adj)
        selectedFilterID = matchPresetFilter(adj)?.id
    }
}
