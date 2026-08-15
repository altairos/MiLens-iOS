//  RedPacketScenePreview —— 红包导出页的分享前多场景模拟预览，
//  从 RedPacketExportView.swift 拆出（ADR-0011 §5 规模守卫拆分批次）。
//  含：场景切换 segmented control + 聊天红包卡片 / 拆红包 / 红包列表三场景模拟。
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
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 160)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(draft.coverTitle.isEmpty ? String(localized: "redpacket.export.defaultTitle") : draft.coverTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.milensTextPrimary)
            // 模拟拆开按钮
            Circle()
                .fill(Color.milensWarning.opacity(0.8))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(localized: "redpacket.export.openButton"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
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
