//  GalleryPageState —— 相册页面决策的纯函数边界
//  （对应源端 viewmodels/GalleryPageState.ets）。
//
//  把分散在页面 build() 与回调中的复杂布尔表达式下沉为可单测的纯函数。
//  页面在调用点构造不可变快照，再传给这里的纯函数。
//  状态本身仍由 @Observable ViewModel 持有，本模块不持有响应式状态。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 状态分组快照（不可变）

/// 相册显示层数据快照（对应源端 GalleryDisplaySnapshot）
struct GalleryDisplaySnapshot: Equatable, Sendable {
    var isLoading: Bool
    var photoCount: Int
    var visibleCount: Int
    var hasMorePhotos: Bool
    var galleryChromeHidden: Bool

    /// 初始加载状态（对应源端 emptyDisplaySnapshot）
    static let initial = GalleryDisplaySnapshot(
        isLoading: true, photoCount: 0, visibleCount: 0,
        hasMorePhotos: false, galleryChromeHidden: false
    )
}

/// 筛选/收藏层状态快照（对应源端 GalleryFilterSnapshot）
struct GalleryFilterSnapshot: Equatable, Sendable {
    var filterEnabled: Bool
    var favoritesEnabled: Bool
    var selectedFilter: GalleryFilter

    /// 未激活的初始快照（对应源端 emptyFilterSnapshot）
    static func initial(filter: GalleryFilter = .empty) -> GalleryFilterSnapshot {
        GalleryFilterSnapshot(filterEnabled: false, favoritesEnabled: false, selectedFilter: filter)
    }
}

/// 扫描任务状态快照（对应源端 GalleryScanSnapshot）
struct GalleryScanSnapshot: Equatable, Sendable {
    var isScanning: Bool
    var scanPaused: Bool
    var showScanCompleteDialog: Bool
    var scanTotal: Int
    var scanFound: Int

    /// 空闲初始快照（对应源端 emptyScanSnapshot）
    static let initial = GalleryScanSnapshot(
        isScanning: false, scanPaused: false,
        showScanCompleteDialog: false, scanTotal: 0, scanFound: 0
    )
}

/// 导入/导出任务状态快照（对应源端 GalleryTaskSnapshot）
struct GalleryTaskSnapshot: Equatable, Sendable {
    var isImporting: Bool
    var isExporting: Bool

    /// 空闲初始快照（对应源端 emptyTaskSnapshot）
    static let initial = GalleryTaskSnapshot(isImporting: false, isExporting: false)
}

// MARK: - 内容区渲染判别

/// 相册主内容区渲染分支（对应源端 GalleryContentKind）
enum GalleryContentKind: Equatable, Sendable {
    case loading          // 全量加载中（spinner）
    case emptyDefault     // 无筛选且无照片 → 完整空状态
    case emptyFiltered    // 启用筛选/收藏但无结果 → 占位
    case content          // 有照片内容
}

// MARK: - 决策纯函数

enum GalleryPageState {

    /// 是否有可见照片（visibleCount > 0）
    static func hasVisiblePhotos(_ display: GalleryDisplaySnapshot) -> Bool {
        display.visibleCount > 0
    }

    /// 是否可以触发 loadMore：必须有更多、当前不在加载中（对应源端 canLoadMore）
    static func canLoadMore(_ display: GalleryDisplaySnapshot) -> Bool {
        guard display.hasMorePhotos, !display.isLoading else { return false }
        return true
    }

    /// 筛选条件本身是否为空（petID=nil 且 dateRange/location 均空）
    static func isFilterEmpty(_ filter: GalleryFilter) -> Bool {
        guard filter.petID == nil, filter.dateRange.isEmpty, filter.location.isEmpty else { return false }
        return true
    }

    /// 当前是否处于「已激活筛选」状态（filterEnabled 或 favoritesEnabled 任一）
    static func isFilterActive(_ filter: GalleryFilterSnapshot) -> Bool {
        filter.filterEnabled || filter.favoritesEnabled
    }

    /// 是否处于「非默认筛选」：筛选面板激活且至少一个条件非空，或仅看收藏激活
    static func isNonDefaultFilter(_ filter: GalleryFilterSnapshot) -> Bool {
        if filter.favoritesEnabled { return true }
        if filter.filterEnabled, !isFilterEmpty(filter.selectedFilter) { return true }
        return false
    }

    /// 任意长任务在运行（扫描 + 导入 + 导出）
    static func isAnyTaskRunning(scan: GalleryScanSnapshot, task: GalleryTaskSnapshot) -> Bool {
        scan.isScanning || task.isImporting || task.isExporting
    }

    /// 是否应禁用顶部 FAB / 多选栏的破坏性操作
    /// （扫描/导入/导出运行中时禁用）
    static func shouldDisableGalleryAction(scan: GalleryScanSnapshot, task: GalleryTaskSnapshot) -> Bool {
        scan.isScanning || task.isImporting || task.isExporting
    }

    /// 相册主区域是否可交互（无任务运行 + 非全量加载）
    static func isGalleryInteractable(
        display: GalleryDisplaySnapshot,
        scan: GalleryScanSnapshot,
        task: GalleryTaskSnapshot
    ) -> Bool {
        !display.isLoading && !isAnyTaskRunning(scan: scan, task: task)
    }

    /// 决定顶部内容区渲染分支（对应源端 resolveContentKind）
    static func resolveContentKind(
        display: GalleryDisplaySnapshot,
        filter: GalleryFilterSnapshot
    ) -> GalleryContentKind {
        if display.isLoading { return .loading }
        if display.visibleCount == 0 {
            if !filter.filterEnabled && !filter.favoritesEnabled { return .emptyDefault }
            return .emptyFiltered
        }
        return .content
    }

    /// 扫描完成弹窗是否应该可见（扫描进行中不显示）
    static func shouldShowScanComplete(_ scan: GalleryScanSnapshot) -> Bool {
        !scan.isScanning && scan.showScanCompleteDialog
    }

    /// 生成扫描进度文案：scanFound / scanTotal。两者均为 0 时返回空串。
    static func resolveScanProgressLabel(_ scan: GalleryScanSnapshot) -> String {
        if scan.scanTotal <= 0 && scan.scanFound <= 0 { return "" }
        return "\(scan.scanFound) / \(scan.scanTotal)"
    }
}
