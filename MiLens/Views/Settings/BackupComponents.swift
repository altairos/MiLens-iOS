//  BackupComponents —— 备份导出相关的独立面板（确认 / 进度 / 分享）。
//  从 SettingsView 拆出（规模守卫，DESIGN.md §6 / AGENTS.md §3）。

import SwiftUI

// MARK: - 备份导出确认对话框

/// 导出前展示预估规模（N 个档案、M 张照片、预计大小），让用户确认后再打包。
/// 避免大库无声产出巨大 ZIP，用户毫无预期。
struct BackupConfirmSheet: View {
    let estimate: BackupEstimate
    let onConfirm: () -> Void

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: estimate.estimatedBytes, countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "externaldrive.badge.timemachine")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "settings.backup.confirmTitle"))
                    .font(.headline)
                    .foregroundStyle(Color.milensTextPrimary)
                // 预估规模
                VStack(spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "pawprint")
                            .foregroundStyle(Color.milensTextSecondary)
                        Text(String(localized: "settings.backup.confirmPets \(estimate.petCount)"))
                        Spacer()
                    }
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(Color.milensTextSecondary)
                        Text(String(localized: "settings.backup.confirmPhotos \(estimate.photoCount)"))
                        Spacer()
                    }
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(Color.milensTextSecondary)
                        Text(String(localized: "settings.backup.confirmSize \(formattedSize)"))
                        Spacer()
                    }
                }
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .background(Color.milensCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

                Text(String(localized: "settings.backup.confirmHint"))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                // 跨平台提示：告知用户备份包是标准 ZIP，电脑上改名即可解压查看
                Text(String(localized: "settings.backup.zipHint"))
                    .font(.caption2)
                    .foregroundStyle(Color.milensTextTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.xs)

                Spacer()

                Button {
                    onConfirm()
                } label: {
                    Text(String(localized: "settings.backup.confirmAction"))
                        .font(.buttonLabel)
                        .foregroundStyle(Color.milensTextOnActionPrimary)
                        .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                        .background(Color.milensActionPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.milensBackground)
        }
        .modalContentWidth()
    }
}

// MARK: - 备份导出阶段进度浮层

/// 导出打包进行中的阶段进度浮层（半透明遮罩 + 阶段文案 + 进度转圈）。
struct ExportProgressOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                ProgressView()
                    .tint(Color.milensActionPrimary)
                Text(message)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
            }
            .padding(Spacing.xl)
            .background(Color.milensCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 备份导出分享面板

/// 导出完成后展示：提供 ShareLink 让用户选择保存位置（Files/iCloud Drive/AirDrop）。
/// 不联网——系统 ShareSheet 完全由用户掌控。多卷时一次分享全部文件。
struct BackupShareSheet: View {
    let urls: [URL]

    private var isMultiVolume: Bool { urls.count > 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.milensSuccess)
                Text(String(localized: "settings.backup.exportReady"))
                    .font(.headline)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(String(localized: "settings.backup.exportReadyHint"))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)

                // 多卷提示：告知用户须保存全部分卷文件
                if isMultiVolume {
                    Text(String(localized: "settings.backup.multiVolumeHint \(urls.count)"))
                        .font(.caption)
                        .foregroundStyle(Color.milensWarning)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.xs)
                }

                // 导出完成也提示：电脑上改名 .zip 即可解压查看照片和元数据
                Text(String(localized: "settings.backup.zipHint"))
                    .font(.caption2)
                    .foregroundStyle(Color.milensTextTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.xs)
                ShareLink(items: urls) {
                    Label(String(localized: "settings.backup.share"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.milensActionPrimary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.milensBackground)
        }
    }
}
