//  EditorDecorationPanelVM —— 装饰面板（相框/贴纸）子状态（对应开发计划 §4 交互规格）。
//  分组浏览（稳定序）/ 添加贴纸（上限 20 + 堆叠落点偏移）/ 相框单选替换 / Pro 锁定触发付费墙。
//  几何与钳制决策走 MiLensKit（createDecorationLayer / isStickerLimitReached），
//  每次面板操作恰好一次 pushHistory（撤销粒度 = 单次操作，替换相框为整体一条记录）。

import CoreGraphics
import Foundation
import MiLensKit
import Observation

@MainActor
@Observable
final class EditorDecorationPanelVM {

    private unowned let owner: EditorViewModel
    private let document: EditorDocumentController

    init(owner: EditorViewModel) {
        self.owner = owner
        self.document = owner.document
    }

    // MARK: - 状态

    /// 当前面板类别（工具驱动：sticker 工具 → 贴纸面板，否则相框）。
    var category: DecorationCategory {
        owner.tool == .sticker ? .sticker : .frame
    }

    /// 分组索引按类别分别记忆（类别间组数不同，避免切换后语义错位）。
    private var frameGroupIndex = 0
    private var stickerGroupIndex = 0

    var groupIndex: Int {
        category == .frame ? frameGroupIndex : stickerGroupIndex
    }

    /// 分组列表（MiLensKit 稳定序：recommended 恒首位，组内 sortOrder 升序）。
    var groups: [(id: String, items: [DecorationItem])] {
        owner.decorationCatalog.groups(for: category)
    }

    /// 当前分组（空目录返回 nil → View 显示空态；索引越界钳制到最后有效组）。
    var currentGroup: (id: String, items: [DecorationItem])? {
        let all = groups
        guard !all.isEmpty else { return nil }
        return all[min(groupIndex, all.count - 1)]
    }

    /// 文档当前相框的 resourcePath（面板选中态；nil → 标题行移除动作禁用）。
    var currentFrameResourcePath: String? {
        document.layers.first { $0.type == .frame }?.resourcePath
    }

    /// 当前选中层是否为贴纸（标题行删除动作可用性）。
    var hasActiveSticker: Bool {
        document.activeLayer?.type == .sticker
    }

    /// 贴纸上限提示（View 展示后 clearStickerLimitToast 复位）。
    private(set) var showsStickerLimitToast = false

    /// 被点击的 Pro 锁定项（View 据此弹付费墙，完成后 clearPaywallIntent 复位）。
    private(set) var pendingPaywallItem: DecorationItem?

    // MARK: - 动作

    func selectGroup(_ index: Int) {
        if category == .frame { frameGroupIndex = index } else { stickerGroupIndex = index }
    }

    /// 添加贴纸：锁定项 → 付费墙；超限（STICKER_LAYER_LIMIT=20）→ 提示；
    /// 否则创建图层（默认几何 + 按 stickerCount 堆叠落点偏移）→ 选中 + 一次 push。
    func addSticker(_ item: DecorationItem, isPro: Bool) {
        guard item.isUsable(isPro: isPro) else {
            pendingPaywallItem = item
            return
        }
        let layers = document.layers
        guard !isStickerLimitReached(layers) else {
            showsStickerLimitToast = true
            return
        }
        var layer = createDecorationLayer(
            from: item,
            canvasWidth: Double(owner.canvasSize.width),
            canvasHeight: Double(owner.canvasSize.height),
            stickerCount: layers.filter { $0.type == .sticker }.count
        )
        document.add(&layer)
        document.pushHistory()
        owner.syncState()
    }

    /// 应用相框（单选替换：移除旧 frame + 添加新层，整体一次 push）。
    /// 点击当前已选相框保持选中，不重复创建（规格 §4.2）。
    func applyFrame(_ item: DecorationItem, isPro: Bool) {
        guard item.isUsable(isPro: isPro) else {
            pendingPaywallItem = item
            return
        }
        guard item.resourcePath != currentFrameResourcePath else { return }
        var layer = createDecorationLayer(
            from: item,
            canvasWidth: Double(owner.canvasSize.width),
            canvasHeight: Double(owner.canvasSize.height)
        )
        removeFrameLayers()
        document.add(&layer)
        // 相框不可选中（阻塞项6：frame 不参与点选/手势），添加后清空选中。
        document.select(nil)
        document.pushHistory()
        owner.syncState()
    }

    /// 删除当前选中贴纸（标题行图标动作；非贴纸选中态静默，规格 §4.1）。
    func deleteActiveSticker() {
        guard let layer = document.activeLayer, layer.type == .sticker else { return }
        document.remove(layer.id)
        document.pushHistory()
        owner.syncState()
    }

    /// 移除相框（标题行图标动作）；无相框时静默（按钮已禁用，双保险）。
    func removeFrame() {
        guard document.layers.contains(where: { $0.type == .frame }) else { return }
        removeFrameLayers()
        document.pushHistory()
        owner.syncState()
    }

    // MARK: - 瞬态复位

    func clearPaywallIntent() { pendingPaywallItem = nil }

    func clearStickerLimitToast() { showsStickerLimitToast = false }

    private func removeFrameLayers() {
        for layer in document.layers where layer.type == .frame {
            document.remove(layer.id)
        }
    }
}
