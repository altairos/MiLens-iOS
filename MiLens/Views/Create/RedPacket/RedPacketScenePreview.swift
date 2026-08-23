//  RedPacketScenePreview —— 红包导出页的分享前多场景模拟预览，
//  从 RedPacketExportView.swift 拆出（ADR-0011 §5 规模守卫拆分批次）。
//  含：场景切换 segmented control + 聊天红包卡片 / 拆红包 / 红包列表三场景模拟。
//  拆红包场景按微信的合成关系展示：导出的 3:4 自定义封面在后，微信自带的
//  橙红前景与“开”按钮在前；系统前景仅存在于预览，不进入导出图片。
//  场景选中状态由宿主持有（selectedScene Binding），预览自身不落页面级状态。

import SwiftUI
import UIKit
import MiLensKit

/// 场景模拟类型（聊天横幅 / 拆红包 / 红包列表）。
enum PreviewScene: String, CaseIterable, Identifiable {
    case redPacketCard  // 聊天横幅（聊天消息）
    case openRedPacket  // 拆红包
    case redPacketList  // 红包列表

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .redPacketCard: return String(localized: "redpacket.export.scene.banner")
        case .openRedPacket: return String(localized: "redpacket.export.scene.open")
        case .redPacketList: return String(localized: "redpacket.export.scene.list")
        }
    }
}

/// 分享前多场景模拟预览：自定义 segmented control + 按选中场景渲染封面模拟图。
struct RedPacketScenePreview: View {
    let image: UIImage
    let draft: RedPacketCoverDraft
    @Binding var selectedScene: PreviewScene

    var body: some View {
        VStack(spacing: 0) {
            // 自定义 segmented control
            HStack(spacing: 0) {
                ForEach(PreviewScene.allCases) { scene in
                    let isSelected = selectedScene == scene
                    Button {
                        selectedScene = scene
                    } label: {
                        Text(scene.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                isSelected
                                    ? Color.white.opacity(0.95)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.milensSealSurface.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.milensSeparator, lineWidth: 1)
            )
            .padding(.bottom, Spacing.sm)

            // 场景内容
            scenePreview
        }
    }

    // MARK: - 场景预览

    private var scenePreview: some View {
        Group {
            switch selectedScene {
            case .redPacketCard:
                redPacketCardScene()
            case .openRedPacket:
                openRedPacketScene()
            case .redPacketList:
                redPacketListScene()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.milensSealSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text(String(localized: "redpacket.export.sceneLabel"))
                .font(.system(size: 10))
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.milensBackground.opacity(0.8))
                .clipShape(Capsule())
                .padding(6)
        }
    }

    // 场景 1：红包卡片（聊天消息）
    private func redPacketCardScene() -> some View {
        HStack(alignment: .top, spacing: 8) {
            avatarPlaceholder
            VStack(alignment: .leading, spacing: 4) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 107)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(draft.coverTitle.isEmpty ? String(localized: "redpacket.export.defaultTitle") : draft.coverTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
            }
            .padding(10)
            .background(Color.milensWarning.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer()
        }
    }

    // 场景 2：拆红包页
    private func openRedPacketScene() -> some View {
        VStack(spacing: 8) {
            WeChatOpenPacketCompositePreview(image: image)
            Text(draft.coverTitle.isEmpty ? String(localized: "redpacket.export.defaultTitle") : draft.coverTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.milensTextPrimary)
        }
    }

    // 场景 3：红包列表
    private func redPacketListScene() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                avatarPlaceholder.frame(width: 28, height: 28)
                Text(draft.petName.isEmpty ? String(localized: "redpacket.export.defaultSender") : draft.petName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.milensTextSecondary)
            }
            HStack(spacing: 6) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 48)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                Text(draft.coverTitle.isEmpty ? String(localized: "redpacket.export.defaultTitle") : draft.coverTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
            }
            .padding(6)
            .background(Color.milensWarning.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.milensTextTertiary.opacity(0.3))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.milensTextTertiary)
            }
    }
}

// MARK: - 微信合成预览

/// 微信领取/拆红包界面的近似合成卡片。
///
/// 关键边界：`image` 是 MiLens 实际导出的 957×1278（3:4）自定义封面；
/// 下方橙红形状与“开”按钮是微信客户端提供的前景，只用于场景说明，不能烘焙进导出图。
private struct WeChatOpenPacketCompositePreview: View {
    let image: UIImage

    private enum Layout {
        static let width: CGFloat = 148
        static let coverHeight: CGFloat = width * 4 / 3
        static let totalHeight: CGFloat = width * 5 / 3
        static let buttonSize: CGFloat = width * 0.24
        static let buttonCenterY: CGFloat = coverHeight * 0.98
        static let cornerRadius: CGFloat = 7
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 用户上传的封面保持完整 3:4 比例；微信系统前景随后覆盖其底部。
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Layout.width, height: Layout.coverHeight)
                .clipped()

            systemForeground
                .fill(Color.milensRedPacketSystemForeground)

            Circle()
                .fill(Color.milensRedPacketSystemButton)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .overlay {
                    Text(String(localized: "redpacket.export.openButton"))
                        .font(.system(size: Layout.buttonSize * 0.42, weight: .regular, design: .serif))
                        .foregroundStyle(Color.milensRedPacketSystemButtonLabel)
                }
                .position(x: Layout.width / 2, y: Layout.buttonCenterY)
        }
        .frame(width: Layout.width, height: Layout.totalHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PreviewScene.openRedPacket.displayName)
    }

    /// 参考真实界面的浅弧形遮罩边界：左侧较高、右侧略低，底部延伸成系统前景。
    private var systemForeground: Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: Layout.coverHeight * 0.86))
            path.addCurve(
                to: CGPoint(x: Layout.width, y: Layout.coverHeight * 0.97),
                control1: CGPoint(x: Layout.width * 0.30, y: Layout.coverHeight * 0.91),
                control2: CGPoint(x: Layout.width * 0.70, y: Layout.coverHeight * 0.99)
            )
            path.addLine(to: CGPoint(x: Layout.width, y: Layout.totalHeight))
            path.addLine(to: CGPoint(x: 0, y: Layout.totalHeight))
            path.closeSubpath()
        }
    }
}
