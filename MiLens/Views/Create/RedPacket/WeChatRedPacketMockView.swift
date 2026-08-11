//  WeChatRedPacketMockView —— 微信红包 4 场景模拟预览（创作 Tab 红包封面项目）。
//
//  模拟微信红包的 4 个展示场景（发红包页/消息气泡/拆红包页/详情页），
//  帮用户在导出前看到封面在真实红包里的视觉效果。
//
//  设计约束（规避商标/外观侵权）：
//  - 不复刻微信 logo、「微信」文字商标、红包特定美术元素
//  - 用中性占位（「红包」通用样式、「開」按钮、金额占位）
//  - 仅模拟布局比例与封面图展示区域，不模仿像素级外观

import SwiftUI
import UIKit
import MiLensKit

/// 红包场景模拟预览（4 个场景切换）。
struct WeChatRedPacketMockView: View {
    let image: UIImage
    let coverTitle: String
    let scene: RedPacketCoverView.RedPacketScene
    let isPro: Bool

    var body: some View {
        switch scene {
        case .open:   openScene
        case .send:   sendScene
        case .bubble: bubbleScene
        case .detail: detailScene
        }
    }

    // MARK: - 拆红包页（最完整展示，封面全屏 + 「開」按钮）

    private var openScene: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // 封面铺底
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                // 底部遮挡区（微信金额+按钮在中下部）
                VStack {
                    Spacer()
                    VStack(spacing: w * 0.04) {
                        Text("¥0.00")
                            .font(.system(size: w * 0.08, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))

                        Text(coverTitle.isEmpty ? "红包" : coverTitle)
                            .font(.system(size: w * 0.035, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))

                        // 「開」按钮占位（中性圆，不复刻微信美术）
                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: w * 0.16, height: w * 0.16)
                            .overlay {
                                Text("開")
                                    .font(.system(size: w * 0.07, weight: .bold))
                                    .foregroundStyle(.red.opacity(0.85))
                            }
                    }
                    .padding(.bottom, h * 0.08)
                }

                // 顶部渐变（增强上方可读性）
                LinearGradient(
                    colors: [Color.black.opacity(0.3), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: h * 0.2)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .aspectRatio(
            Double(WeChatRedPacketSpec.coverImageWidth) / Double(WeChatRedPacketSpec.coverImageHeight),
            contentMode: .fit)
    }

    // MARK: - 发红包页（封面缩略 + 金额输入样式）

    private var sendScene: some View {
        VStack(spacing: 0) {
            // 顶部封面缩略
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipped()

            // 模拟金额输入区
            VStack(spacing: Spacing.sm) {
                Text("金额")
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
                Text("¥ _ _ _ . _ _")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.milensTextPrimary)
                Divider()
                    .padding(.vertical, Spacing.xs)
                Text("恭喜发财，大吉大利")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(Color.milensCard)

            Spacer()

            // 模拟红包按钮
            Text("红包")
                .font(.bodyPrimary.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.md)
                .background(Color.red.opacity(0.8))
                .clipShape(Capsule())
                .padding(.bottom, Spacing.lg)
        }
        .background(Color.milensBackground)
    }

    // MARK: - 消息气泡（聊天列表里的红包气泡）

    private var bubbleScene: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // 封面缩略气泡
            VStack(spacing: 0) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 70)
                    .clipped()
                HStack {
                    Text(coverTitle.isEmpty ? "红包" : coverTitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text("红包")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color.red.opacity(0.85))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))

            Spacer()
        }
        .padding(Spacing.lg)
        .background(Color.milensBackground)
    }

    // MARK: - 详情页（封面 + 封面故事区下拉）

    private var detailScene: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 封面主体
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipped()

                // 封面故事区
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("封面故事")
                        .font(.bodyPrimary.weight(.medium))
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(coverTitle.isEmpty ? "我的红包封面" : "\(coverTitle) 的故事")
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                    Text("由 MiLens 制作")
                        .font(.caption)
                        .foregroundStyle(Color.milensTextTertiary)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.milensCard)
            }
        }
        .disabled(true) // 预览用，不滚动
    }
}
