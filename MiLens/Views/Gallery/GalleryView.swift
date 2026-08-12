//  GalleryView —— 相册网格视图（对应源端 pages/GalleryPage.ets）。
//  LazyVGrid 虚拟化 + 分页加载 + 扫描入口 + 扫描完成弹窗。
//  内容区渲染分支由 GalleryPageState.resolveContentKind 决定。

import SwiftUI
import UIKit
import MiLensKit

struct GalleryView: View {
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement

    @State private var viewModel: GalleryViewModel?
    @State private var navigationPath = NavigationPath()
    @State private var pendingDeleteID: UUID?
    @State private var isManageMode = false
    /// 手动归属 sheet 的照片列表（非空=显示 sheet；单张=contextMenu，多张=批量）
    @State private var assignmentPhotos: [Photo] = []
    /// 锁定照片点击时展示的提示 sheet（提供「续费 / 去清理」）。
    @State private var showLockedPhotoSheet = false
    /// 批量删除确认弹窗
    @State private var showBatchDeleteConfirm = false
    /// 从设置页/降级 sheet 跳转来的「存储管理」请求标志。
    @AppStorage("storageManageRequested") private var storageManageRequested = false
    @Namespace private var photoHeroNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .background(Color.milensPaper)
        .onAppear {
            if viewModel == nil {
                let vm = factory.makeGalleryViewModel()
                vm.isPro = entitlement.isPro
                vm.loadInitial()
                viewModel = vm
            }
            // 从设置页/降级 sheet 跳转来：进入存储管理模式
            if storageManageRequested {
                storageManageRequested = false
                viewModel?.enterStorageManageMode()
                isManageMode = true
            }
        }
        .onChange(of: entitlement.isPro) { _, isPro in
            viewModel?.updateProStatus(isPro)
        }
        .onChange(of: storageManageRequested) { _, requested in
            if requested {
                storageManageRequested = false
                viewModel?.enterStorageManageMode()
                isManageMode = true
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.showQuotaPaywall ?? false },
            set: { viewModel?.showQuotaPaywall = $0 }
        )) {
            NavigationStack { PaywallView() }
        }
        .sheet(isPresented: $showLockedPhotoSheet) {
            QuotaDowngradeSheet()
        }
        .alert(String(format: String(localized: "photo.batch.delete.confirm %lld"),
                      viewModel?.selectedPhotoIDs.count ?? 0),
               isPresented: $showBatchDeleteConfirm) {
            Button("删除", role: .destructive) {
                viewModel?.deleteSelected()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会从咪Lens 的整理记录中移除，不会删除系统相册原图。")
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .alert("删除这张照片？", isPresented: Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteID {
                    viewModel?.deletePhoto(id: id)
                }
                pendingDeleteID = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteID = nil
            }
        } message: {
            Text("只会从咪Lens 的整理记录中移除，不会删除系统相册原图。")
        }
        .safeAreaInset(edge: .bottom) {
            if let vm = viewModel, vm.isMultiSelectMode {
                GalleryBatchBar(
                    selectedCount: vm.selectedPhotoIDs.count,
                    onAssign: {
                        assignmentPhotos = vm.photos.filter { vm.selectedPhotoIDs.contains($0.id) }
                    },
                    onDelete: {
                        showBatchDeleteConfirm = true
                    }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { !assignmentPhotos.isEmpty },
            set: { if !$0 { assignmentPhotos.removeAll() } }
        )) {
            if !assignmentPhotos.isEmpty {
                PetAssignmentSheet(photos: assignmentPhotos) {
                    // 归属成功：清空多选选择并重新加载（筛选/归属变化）
                    viewModel?.selectedPhotoIDs.removeAll()
                    viewModel?.refreshAfterAssignment()
                }
            }
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private func content(_ vm: GalleryViewModel) -> some View {
        let kind = GalleryPageState.resolveContentKind(
            display: vm.displaySnapshot, filter: vm.filterSnapshot
        )
        Group {
            switch kind {
            case .loading:
                ProgressView()
            case .emptyDefault:
                emptyDefaultView(vm)
            case .emptyFiltered:
                emptyFilteredView
            case .content:
                photoGrid(vm)
            }
        }
        // 进度条与完成弹窗挂载在内容区外层：空状态/筛选空态下扫描也有反馈
        // （此前仅 photoGrid 分支可见，空状态点「开始扫描」看起来毫无反应）。
        .overlay(alignment: .top) {
            if vm.isScanning {
                scanProgressBar(vm)
            }
        }
        .sheet(isPresented: Binding(
            get: { vm.showScanCompleteDialog },
            set: { vm.showScanCompleteDialog = $0 }
        )) {
            ScanCompleteSheet(viewModel: vm)
        }
    }

    // MARK: - 空状态

    private func emptyDefaultView(_ vm: GalleryViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.milensTextSecondary)
            Text("还没有照片")
                .font(.displayMedium)
            Text("扫描系统相册，自动发现你的宠物照片")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            Button {
                vm.startScan()
            } label: {
                Label("开始扫描", systemImage: "magnifyingglass")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.milensActionPrimary)
            .disabled(vm.isScanning)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilteredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.ribbon.angled")
                .font(.system(size: 48))
                .foregroundStyle(Color.milensTextSecondary)
            Text("没有符合条件的照片")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 照片网格

    private func photoGrid(_ vm: GalleryViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                galleryHeader(vm)
                overLimitBanner(vm)
                filterChips(vm)
                let visiblePhotos = vm.filteredPhotos
                let photoByID = Dictionary(uniqueKeysWithValues: vm.photos.map { ($0.id, $0) })
                let sections = GallerySectionLogic.groupPhotos(visiblePhotos.map {
                    GalleryPhoto(id: $0.id, takenAt: $0.takenAt, petID: $0.pet?.id)
                })

                ForEach(Array(sections.enumerated()), id: \.offset) { sectionIndex, section in
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.editorialSection)
                                .foregroundStyle(Color.milensTextPrimary)
                                .padding(.horizontal, Spacing.pagePad)
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            Text("未标注日期")
                                .font(.titleStandard)
                                .foregroundStyle(Color.milensTextSecondary)
                                .padding(.horizontal, Spacing.pagePad)
                        }

                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(Array(section.photos.enumerated()), id: \.element.id) { itemIndex, projection in
                                if let photo = photoByID[projection.id] {
                                    photoCell(photo: photo, vm: vm)
                                        .onAppear {
                                            let isLastSection = sectionIndex == sections.count - 1
                                            let isNearEnd = itemIndex >= section.photos.count - 3
                                            if isLastSection && isNearEnd && visiblePhotos.count >= vm.photos.count - 10 {
                                                vm.loadMore()
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
    }

    private func galleryHeader(_ vm: GalleryViewModel) -> some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            // 文楷标题 + 张数（对照 Figma #211:247-248）
            Text("照片")
                .font(.custom("LXGWWenKai-Regular", size: 24, relativeTo: .largeTitle))
                .foregroundStyle(Color.milensTextPrimary)
            Text("\(vm.totalPhotoCount) 张")
                .font(.system(size: 11))
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.bottom, 2)
            Spacer()
            // 选择按钮（对照 Figma #211:249-250）
            Button {
                isManageMode.toggle()
                if vm.isMultiSelectMode != isManageMode {
                    vm.toggleMultiSelect()
                }
            } label: {
                Text("选择")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.milensTextPrimary)
                    .frame(width: 66, height: 44)
                    .background(Color.milensGrouped)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.lg)
    }

    /// 超额横幅：进入存储管理模式时显示，引导用户删除多余照片或续费。
    @ViewBuilder
    private func overLimitBanner(_ vm: GalleryViewModel) -> some View {
        if vm.showOverLimitBanner {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.system(size: Sizing.iconSm))
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "quota.downgrade.banner"))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.milensAccentWash)
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.sm)
        }
    }

    @ViewBuilder
    private func filterChips(_ vm: GalleryViewModel) -> some View {
        let pets = vm.pets.map { GalleryFilterPet(id: $0.id, name: $0.name) }
        let chips = GalleryFilterLogic.buildChips(pets: pets, selectedPetID: vm.selectedFilter.petID)
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                ForEach(chips) { chip in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: Motion.durationFast)) {
                            vm.selectPet(chip.petID)
                        }
                    } label: {
                        Text(chip.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(chip.isSelected ? Color.white : Color.milensTextSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(chip.isSelected ? Color.milensActionPrimary : Color.white)
                            .overlay(
                                Capsule()
                                    .stroke(Color.milensBorder, lineWidth: chip.isSelected ? 0 : 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chip.isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Spacing.pagePad)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func photoCell(photo: Photo, vm: GalleryViewModel) -> some View {
        let isLocked = vm.isLocked(photo.id)
        Group {
            if vm.isMultiSelectMode {
                // 多选模式：锁定照片可正常选中删除（不显示蒙层）
                Button {
                    vm.toggleSelection(photo.id)
                } label: {
                    PhotoThumbnailCell(photo: photo, isMultiSelect: true,
                                       isSelected: vm.selectedPhotoIDs.contains(photo.id))
                }
                .buttonStyle(.plain)
            } else if isLocked {
                // 非多选 + 锁定：显示锁标蒙层，点击弹提示（不进大图）
                Button {
                    showLockedPhotoSheet = true
                } label: {
                    LockedPhotoThumbnailCell(photo: photo)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    // 锁定照片可删除，移除「创作」等需解锁的操作
                    Button(role: .destructive) {
                        pendingDeleteID = photo.id
                    } label: {
                        Label("从咪Lens 移除", systemImage: "trash")
                    }
                }
            } else {
                NavigationLink {
                    PhotoViewView(
                        photoID: photo.id,
                        heroNamespace: photoHeroNamespace,
                        heroID: photo.id
                    )
                } label: {
                    PhotoThumbnailCell(
                        photo: photo,
                        isMultiSelect: false,
                        isSelected: false,
                        heroNamespace: photoHeroNamespace,
                        heroID: photo.id
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        vm.setFavorite(photo)
                    } label: {
                        Label(photo.isFavorite ? "取消收藏" : "收藏", systemImage: photo.isFavorite ? "heart.slash" : "heart")
                    }
                    Button {
                        assignmentPhotos = [photo]
                    } label: {
                        Label(String(localized: "photo.assign.title"), systemImage: "person.crop.circle.badge.plus")
                    }
                    NavigationLink(value: Route.beadPattern(photoID: photo.id)) {
                        Label("创作拼豆图纸", systemImage: "square.grid.3x3.topleft.filled")
                    }
                    Button(role: .destructive) {
                        pendingDeleteID = photo.id
                    } label: {
                        Label("从咪Lens 移除", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func scanProgressBar(_ vm: GalleryViewModel) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("正在扫描 \(vm.scanProgressText)")
                .font(.caption)
            Spacer()
            Button("取消") { vm.cancelScan() }
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(reduceTransparency ? AnyShapeStyle(Color.milensElevated) : AnyShapeStyle(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
        .padding()
    }
}

// MARK: - 缩略图单元格

private struct PhotoThumbnailCell: View {
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
                        .font(.system(size: 11, weight: .bold))
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
private struct LockedPhotoThumbnailCell: View {
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
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)

            // 右上角 Pro 角标
            VStack {
                HStack {
                    Spacer()
                    Text(String(localized: "quota.locked.badge"))
                        .font(.system(size: 9, weight: .bold))
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
            image = nil
            // 本地文件加载——在后台线程解码；捕获 path 值（String, Sendable），
            // 避免把非 Sendable 的 self（View struct）送入 detached 隔离区（严格并发）。
            let targetPath = path
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: targetPath)
            }.value
            self.image = loaded
        }
    }
}

// MARK: - 扫描完成弹窗

private struct ScanCompleteSheet: View {
    let viewModel: GalleryViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: viewModel.scanFailed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 48))
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

private struct GalleryBatchBar: View {
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
            .tint(Color.red)
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

#Preview {
    NavigationStack {
        GalleryView()
    }
}
