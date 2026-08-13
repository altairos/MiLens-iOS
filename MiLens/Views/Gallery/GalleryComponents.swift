//  GalleryComponents —— 相册页拆出的独立组件（缩略图单元、加载器、扫描弹窗、批量栏）。
//  从 GalleryView 拆出（规模守卫，DESIGN.md §6 / AGENTS.md §3）。

import SwiftUI
import UIKit

// MARK: - 缩略图单元格

struct PhotoThumbnailCell: View {
    let photo: Photo
    let isMultiSelect: Bool
    let isSelected: Bool
    let heroNamespace: Namespace.ID?
    let heroID: UUID?

    init(
        photo: Photo,
        isMultiSelect: Bool,
        isSelected: Bool,
        heroNamespace: Namespace.ID? = nil,
        heroID: UUID? = nil
    ) {
        self.photo = photo
        self.isMultiSelect = isMultiSelect
        self.isSelected = isSelected
        self.heroNamespace = heroNamespace
        self.heroID = heroID
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let heroNamespace, let heroID {
                ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .matchedGeometryEffect(id: heroID, in: heroNamespace)
            } else {
                ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if isMultiSelect {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.milensActionPrimary : .white)
                    .padding(4)
            }
            if photo.isFavorite {
                // 珊瑚圆形 badge（对照 Figma #211:258-259）
                ZStack {
                    Circle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 25, height: 25)
                    Text("\u{2665}")
                        .font(.editorialMetadata)
                        .foregroundStyle(.white)
                }
                .padding(5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // M4：缩略图为装饰性图形，合并为单一无障碍元素（日期 + 收藏/选择状态）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        // 无障碍拼装：片段各自本地化（含前导分隔符，翻译可整体调整顺序与标点）。
        var text = String(localized: "a11y.gallery.photo")
        if let takenAt = photo.takenAt {
            let comps = Calendar.current.dateComponents([.month, .day], from: takenAt)
            if let month = comps.month, let day = comps.day {
                text += String(localized: "a11y.gallery.date \(month) \(day)")
            }
        }
        if isMultiSelect && isSelected { text += String(localized: "a11y.gallery.selected") }
        if photo.isFavorite { text += String(localized: "a11y.gallery.favorite") }
        return text
    }
}

// MARK: - 锁定照片缩略图单元格

/// 配额锁定照片的缩略图：半透明蒙层 + 居中锁标 + 角标「Pro」。
/// 可见但不可进大图，点击弹提示（续费 / 去清理）。
struct LockedPhotoThumbnailCell: View {
    let photo: Photo

    var body: some View {
        ZStack {
            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // 半透明蒙层
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.35))

            // 居中锁标
            Image(systemName: "lock.fill")
                .font(.system(size: Sizing.iconMd, weight: .medium))
                .foregroundStyle(.white)

            // 右上角 Pro 角标
            VStack {
                HStack {
                    Spacer()
                    Text(String(localized: "quota.locked.badge"))
                        .font(.system(size: 9, weight: .bold)) // ui-token:ok 微型角标
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.milensActionPrimary)
                        .clipShape(Capsule())
                        .padding(5)
                }
                Spacer()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "a11y.gallery.lockedPhoto"))
    }
}

// MARK: - 缩略图加载（本地文件）

struct ThumbnailImage: View {
    let path: String
    @Environment(\.thumbnailCache) private var cache
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Rectangle()
                    .fill(Color.milensGrouped)
                    .overlay(ProgressView().scaleEffect(0.5))
            }
        }
        .task(id: path) {
            // 按路径重启任务：照片编辑后 URI 改变但模型 ID 不变时，
            // .task(id: path) 确保加载任务重启；路径变化时清除旧图强制重载。
            guard !path.isEmpty else { return }
            // 1. 先查 LRU 缓存（命中则免解码，滚动复用场景显节省）
            if let cached = cache.get(path) {
                image = cached
                return
            }
            image = nil
            // 2. 未命中：后台解码后写入缓存
            //    本地文件加载——在后台线程解码；捕获 path 值（String, Sendable），
            //    避免把非 Sendable 的 self（View struct）送入 detached 隔离区（严格并发）。
            let targetPath = path
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: targetPath)
            }.value
            self.image = loaded
            // 3. 写入缓存（供后续复用）
            if let loaded {
                cache.put(path, image: loaded)
            }
        }
    }
}

// MARK: - 扫描完成弹窗

struct ScanCompleteSheet: View {
    let viewModel: GalleryViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: viewModel.scanFailed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 48)) // ui-token:ok 结果态装饰大图标
                    .foregroundStyle(viewModel.scanFailed ? Color.milensWarning : Color.milensPrimary)

                Text(viewModel.scanFailed ? "扫描未完成" : "扫描完成")
                    .font(.displayMedium)

                Text(viewModel.scanCompleteMessage)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // 导入入口覆盖全部扫描发现的宠物照片（预匹配 + 未匹配）——
                // 预匹配只是只读判定，真正归属写入在导入时完成
                let pendingCount = viewModel.unassignedPetUris.count + viewModel.matchedPetUris.count
                if pendingCount > 0 {
                    Button {
                        viewModel.importScannedPhotos()
                    } label: {
                        Label("导入 \(pendingCount) 张照片", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.milensActionPrimary)
                    .disabled(viewModel.isImporting)
                }

                // 权限被拒时提供系统设置引导（「设置 → 隐私 → 照片」）
                if viewModel.permissionDenied {
                    Button("去设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.bodyPrimary)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.milensActionPrimary)
                }

                Button("完成") {
                    viewModel.showScanCompleteDialog = false
                }
                .font(.bodyPrimary)
            }
            .padding()
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 多选批量操作栏

struct GalleryBatchBar: View {
    let selectedCount: Int
    let onAssign: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(String(localized: "photo.batch.selected \(selectedCount)"))
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
            Spacer()
            Button(action: onAssign) {
                Label(String(localized: "photo.batch.assign"), systemImage: "person.crop.circle.badge.plus")
                    .font(.bodySecondary.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.milensActionPrimary)
            .disabled(selectedCount == 0)

            Button(action: onDelete) {
                Label(String(localized: "photo.batch.delete"), systemImage: "trash")
                    .font(.bodySecondary.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.milensDanger)
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.vertical, Spacing.sm)
        .background(Color.milensElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.milensBorder)
                .frame(height: 0.5)
        }
    }
}
