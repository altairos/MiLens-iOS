//  SharePreviewSheet —— ADR-0010 分享增强：引导式平台选择 + 系统 ShareSheet。
//
//  不集成各平台 SDK（违背纯 Swift 原则、审核成本高），改用预览成品 +
//  平台图标横排引导 → 触发系统 ShareSheet（自动含已安装平台 App）。
//  水印图片自带传播属性：其他用户看到「MiLens」→ 搜索下载。

import SwiftUI
import MiLensKit

/// 分享预览数据的 Identifiable 包装（sheet(item:) 需要）。
struct SharePreviewData: Identifiable {
    let id = UUID()
    let image: UIImage
    let url: URL
}

/// 分享预览面板（bottom sheet）。
///
/// 展示作品预览图 + 平台引导图标行，点击任意平台触发系统 ShareSheet。
struct SharePreviewSheet: View {
    /// 预览图（导出的成品 PNG/JPEG）。
    let previewImage: UIImage
    /// 分享文件 URL（系统 ShareSheet 使用）。
    let shareURL: URL
    /// 分享文案（可选，随图片一起分享）。
    var shareText: String = ""
    /// 关闭回调。
    var onDismiss: () -> Void

    @State private var showSystemShare = false

    var body: some View {
        VStack(spacing: 0) {
            // 拖拽指示条
            Capsule()
                .fill(Color.milensTextTertiary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)

            Text(String(localized: "share.sheet.title"))
                .font(.titleStandard)
                .foregroundStyle(Color.milensTextPrimary)

            Text(String(localized: "share.sheet.subtitle"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.top, Spacing.xs)

            // 预览图
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .padding(.vertical, Spacing.xl)

            // 平台引导行（平台名为专有名词，仍走本地化 key 便于各语言市场适配）
            HStack(spacing: Spacing.xl) {
                platformButton(icon: "message.fill", label: String(localized: "share.platform.wechat"), tint: .milensBrandWechat)
                platformButton(icon: "person.2.fill", label: String(localized: "share.platform.moments"), tint: .milensBrandWechat)
                platformButton(icon: "book.fill", label: String(localized: "share.platform.rednote"), tint: .milensBrandRedNote)
                platformButton(icon: "music.note", label: String(localized: "share.platform.douyin"), tint: .black)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.bottom, Spacing.lg)

            // 更多（系统分享面板）
            Button {
                showSystemShare = true
            } label: {
                Label(String(localized: "share.sheet.morePlatforms"), systemImage: "square.and.arrow.up")
                    .font(.bodyPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
            }
            .buttonStyle(.bordered)
            .tint(Color.milensActionPrimary)
            .padding(.horizontal, Spacing.pagePad)

            // 水印提示（免费版）
            Text(String(localized: "share.sheet.watermarkHint"))
                .font(.caption)
                .foregroundStyle(Color.milensTextTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxl)
        }
        .background(Color.milensBackground)
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showSystemShare) {
            ShareSheet(items: shareItems)
        }
        .onAppear { MetricsRecorder().record(.shareSheetOpened) }
    }

    /// 系统 ShareSheet 的 items（图片 URL + 可选文案）。
    private var shareItems: [Any] {
        var items: [Any] = []
        if !shareText.isEmpty { items.append(shareText) }
        items.append(shareURL)
        return items
    }

    /// 平台引导按钮。
    @ViewBuilder
    private func platformButton(icon: String, label: String, tint: Color) -> some View {
        Button {
            showSystemShare = true
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: Sizing.iconLg))
                    .foregroundStyle(tint)
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                    .background(tint.opacity(0.1))
                    .clipShape(Circle())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}
