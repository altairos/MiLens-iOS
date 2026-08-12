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

            // 成品卡片预览（居中 + 大阴影）
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 210, maxHeight: 263)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.milensSeparator, lineWidth: 0.5)
                )
                .elevation(.medium)
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

            // 系统分享目标
            Text(String(localized: "share.panel.destinations"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)

            HStack(spacing: 0) {
                shareDestination(icon: "shareplay", label: "AirDrop")
                shareDestination(icon: "message.fill", label: String(localized: "share.platform.wechat"), tint: .milensBrandWechat)
                shareDestination(icon: "message", label: "iMessage")
                shareDestination(icon: "ellipsis", label: String(localized: "share.panel.more"))
            }
            .padding(.horizontal, Spacing.lg)
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

    // MARK: - 分享目标

    @ViewBuilder
    private func shareDestination(icon: String, label: String, tint: Color = .milensTextSecondary) -> some View {
        Button { showSystemShare = true } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(label)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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

    /// 系统 ShareSheet 的 items（图片 URL + 可选文案）。
    private var shareItems: [Any] {
        var items: [Any] = []
        if !shareText.isEmpty { items.append(shareText) }
        items.append(shareURL)
        return items
    }
}

// MARK: - Spacing 扩展（底部安全区）

private extension Spacing {
    /// 底部安全区高度（非全面屏 0 / 全面屏 34pt）。
    static var bottomSafe: CGFloat { 34 }
}
