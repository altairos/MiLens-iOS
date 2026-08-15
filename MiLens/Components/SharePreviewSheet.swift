//  SharePreviewSheet —— Figma `12 · Output / Share Preview` #422:849。
//
//  编辑式成品预览 + 底部系统分享面板（圆角 22px 弹起）。
//  不集成各平台 SDK（违背纯 Swift 原则），改用预览成品 +
//  系统分享目标引导 → 触发系统 ShareSheet（自动含已安装平台 App）。
//  水印图片自带传播属性：其他用户看到「MiLens」→ 搜索下载。

import SwiftUI
import MiLensKit

/// 分享预览数据的 Identifiable 包装（sheet(item:) 需要）。
struct SharePreviewData: Identifiable {
    let id = UUID()
    let image: UIImage
    let url: URL
    /// 同一份分页作品的后续预览图与文件；单图调用方保持为空。
    var additionalImages: [UIImage] = []
    var additionalURLs: [URL] = []
    /// 文件名（如 "MiLens_小满_伙伴纪念卡_001.png"），nil 时隐藏。
    var filename: String? = nil
    /// 导出规格（如 "1080 × 1350 · PNG · 2.4 MB"），nil 时隐藏。
    var spec: String? = nil
}

/// 分享预览面板（bottom sheet 或 fullScreenCover）。
///
/// 对照 Figma `12 · Output / Share Preview`：
/// - 预览区：Overline + 编辑式标题 + 成品卡片预览（大阴影）
/// - 底部 System Share Panel：文件名 + 规格 + 系统分享目标 + 隐私说明 + CreationActionBar
struct SharePreviewSheet: View {
    /// 预览图（导出的成品 PNG/JPEG）。
    let previewImage: UIImage
    /// 分享文件 URL（系统 ShareSheet 使用）。
    let shareURL: URL
    /// 分页作品的后续预览图与分享文件。
    var additionalPreviewImages: [UIImage] = []
    var additionalShareURLs: [URL] = []
    /// 分享文案（可选，随图片一起分享）。
    var shareText: String = ""
    /// 文件名（如 "MiLens_小满_伙伴纪念卡_001.png"）。
    var filename: String? = nil
    /// 导出规格（如 "1080 × 1350 · PNG · 2.4 MB"）。
    var spec: String? = nil
    /// 主按钮文案（默认"分享成品"）。
    var primaryLabel: String = String(localized: "share.action.share")
    /// 次按钮文案（默认"存到系统图库"）。
    var secondaryLabel: String = String(localized: "share.action.saveLibrary")
    /// 主按钮回调（默认触发系统分享）。
    var onPrimary: (() -> Void)? = nil
    /// 次按钮回调（默认无操作，由调用方实现保存）。
    var onSecondary: (() -> Void)? = nil
    /// 关闭回调。
    var onDismiss: () -> Void

    @State private var showSystemShare = false
    /// 沉浸式查看状态
    @State private var showImmersive = false
    @State private var immersiveScale: CGFloat = 1
    @State private var immersiveLastScale: CGFloat = 1
    @State private var immersiveOffset: CGSize = .zero
    @State private var immersiveLastOffset: CGSize = .zero
    @State private var selectedPageIndex = 0

    private var previewImages: [UIImage] {
        [previewImage] + additionalPreviewImages
    }

    private var activePreviewImage: UIImage {
        previewImages[min(selectedPageIndex, previewImages.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            previewArea
            sharePanel
        }
        .background(Color.milensBackground)
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showSystemShare) {
            ShareSheet(items: shareItems)
        }
        .onAppear { MetricsRecorder().record(.shareSheetOpened) }
        .overlay {
            if showImmersive {
                immersiveViewer
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Motion.durationNormal), value: showImmersive)
    }

    // MARK: - 沉浸式查看器

    /// 全屏暗色查看器：双击缩放、捏合缩放、拖拽平移（放大时）/ 下滑关闭（原尺寸时）。
    private var immersiveViewer: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: activePreviewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(immersiveScale)
                    .offset(immersiveOffset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                immersiveScale = PhotoViewGestureMath.clampScale(immersiveLastScale * value.magnification)
                            }
                            .onEnded { _ in
                                immersiveLastScale = immersiveScale
                                if immersiveScale <= 1 { resetImmersive() }
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if immersiveScale > 1 {
                                    let maxPan = PhotoViewGestureMath.computeMaxPanOffset(
                                        containerWidth: geo.size.width, imageScale: immersiveScale)
                                    immersiveOffset = CGSize(
                                        width: PhotoViewGestureMath.clampPanOffset(
                                            immersiveLastOffset.width + value.translation.width, maxPan: maxPan),
                                        height: PhotoViewGestureMath.clampPanOffset(
                                            immersiveLastOffset.height + value.translation.height, maxPan: maxPan))
                                } else {
                                    immersiveOffset = CGSize(width: 0, height: value.translation.height)
                                }
                            }
                            .onEnded { value in
                                if immersiveScale > 1 {
                                    immersiveLastOffset = immersiveOffset
                                } else if value.translation.height > 100 {
                                    closeImmersive()
                                } else {
                                    withAnimation(.spring(duration: Motion.durationNormal, bounce: 0.1)) {
                                        immersiveOffset = .zero
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: Motion.durationNormal, bounce: 0.1)) {
                            if immersiveScale > 1 {
                                resetImmersive()
                            } else {
                                immersiveScale = 2.5
                                immersiveLastScale = 2.5
                            }
                        }
                    }
            }
            .overlay(alignment: .topLeading) {
                Button {
                    closeImmersive()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 36, height: 36)
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold)) // ui-token:ok SF Symbol 光学图标尺寸
                            .foregroundStyle(Color.milensInk)
                    }
                }
                .padding(.leading, Spacing.lg)
                .padding(.top, 12)
            }
            .overlay(alignment: .bottom) {
                if previewImages.count > 1 {
                    pageStepper(foreground: .white, background: Color.black.opacity(0.55))
                        .padding(.bottom, Spacing.xl)
                }
            }
        }
    }

    private func resetImmersive() {
        immersiveScale = 1
        immersiveLastScale = 1
        immersiveOffset = .zero
        immersiveLastOffset = .zero
    }

    private func closeImmersive() {
        withAnimation(.easeInOut(duration: Motion.durationNormal)) {
            showImmersive = false
            resetImmersive()
        }
    }

    // MARK: - 预览区

    private var previewArea: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack {
                Button { onDismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: Sizing.iconLg, weight: .semibold))
                        .foregroundStyle(Color.milensTextPrimary)
                        .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                }
                Spacer()
                Text(String(localized: "share.preview.title"))
                    .font(.uiTitle)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Button(String(localized: "share.preview.close")) { onDismiss() }
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensActionPrimary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)

            // Overline + 编辑式标题
            VStack(alignment: .leading, spacing: 0) {
                EditorialOverline(text: String(localized: "share.preview.overline"))
                Text(String(localized: "share.preview.headline"))
                    .font(.editorialSection)
                    .foregroundStyle(Color.milensTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.lg)

            // 成品卡片预览（分页作品可逐页翻看；点击进入沉浸式查看）
            VStack(spacing: Spacing.sm) {
                Button {
                    showImmersive = true
                    Haptics.light()
                } label: {
                    Image(uiImage: activePreviewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 210, maxHeight: 263)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.milensSeparator, lineWidth: 0.5)
                        )
                        .elevation(Elevation.medium)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 12)) // ui-token:ok SF Symbol 光学图标尺寸
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.4), in: Circle())
                        }
                }
                .buttonStyle(.plain)

                if previewImages.count > 1 {
                    pageStepper(
                        foreground: Color.milensTextPrimary,
                        background: Color.milensGrouped
                    )
                }
            }
            .padding(.top, Spacing.xl)

            Spacer(minLength: Spacing.lg)
        }
    }

    // MARK: - 系统分享面板（圆角弹起）

    private var sharePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 铜色索引条
            CopperIndexBar()

            // 文件信息
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "share.panel.title"))
                    .font(.uiTitle)
                    .foregroundStyle(Color.milensTextPrimary)
                if let filename {
                    Text(filename)
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                }
                if let spec {
                    Text(spec)
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)

            Divider()
                .overlay(Color.milensSeparator)
                .padding(.top, Spacing.sm)

            // 隐私说明
            Text(String(localized: "share.panel.privacy"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)

            // 操作栏
            CreationActionBar(
                primaryLabel: primaryLabel,
                secondaryLabel: secondaryLabel,
                primaryAction: { handlePrimary() },
                secondaryAction: { handleSecondary() }
            )
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.bottomSafe)
        }
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - 动作

    private func handlePrimary() {
        if let onPrimary {
            onPrimary()
        } else {
            showSystemShare = true
        }
    }

    private func handleSecondary() {
        onSecondary?()
    }

    private func changePage(by offset: Int) {
        let next = min(max(selectedPageIndex + offset, 0), previewImages.count - 1)
        guard next != selectedPageIndex else { return }
        withAnimation(.easeInOut(duration: Motion.durationFast)) {
            selectedPageIndex = next
            resetImmersive()
        }
    }

    private func pageStepper(foreground: Color, background: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Button { changePage(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .disabled(selectedPageIndex == 0)
            .opacity(selectedPageIndex == 0 ? 0.35 : 1)

            Text(String(format: "%02d / %02d", selectedPageIndex + 1, previewImages.count))
                .font(.editorialMetadata)
                .monospacedDigit()

            Button { changePage(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .disabled(selectedPageIndex == previewImages.count - 1)
            .opacity(selectedPageIndex == previewImages.count - 1 ? 0.35 : 1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
    }

    /// 系统 ShareSheet 的 items（图片 URL + 可选文案）。
    private var shareItems: [Any] {
        var items: [Any] = []
        if !shareText.isEmpty { items.append(shareText) }
        items.append(contentsOf: [shareURL] + additionalShareURLs)
        return items
    }
}

// MARK: - Spacing 扩展（底部安全区）

private extension Spacing {
    /// 底部安全区高度（非全面屏 0 / 全面屏 34pt）。
    static var bottomSafe: CGFloat { 34 }
}
