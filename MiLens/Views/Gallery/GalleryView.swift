//  GalleryView —— 相册网格视图（对应源端 pages/GalleryPage.ets）。
//  LazyVGrid 虚拟化 + 分页加载 + 扫描入口 + 扫描完成弹窗。
//  内容区渲染分支由 GalleryPageState.resolveContentKind 决定。

import SwiftUI
import MiLensKit

struct GalleryView: View {
    @Environment(\.photoRepository) private var photoRepo
    @Environment(\.petRepository) private var petRepo
    @Environment(\.photoLibraryAccess) private var photoLibrary
    @Environment(\.visionService) private var vision
    @Environment(\.fileStorage) private var fileStorage
    @Environment(\.clipInferenceService) private var clipInferenceService
    @Environment(\.scanCursorStore) private var scanCursorStore
    @Environment(\.mediaLifecycleService) private var mediaLifecycleService

    @State private var viewModel: GalleryViewModel?
    @State private var navigationPath = NavigationPath()
    @State private var pendingDeleteID: UUID?
    @Namespace private var photoHeroNamespace

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                // URL.documentsDirectory（iOS 16+）等价于 urls(for: .documentDirectory).first
                let docs = URL.documentsDirectory
                let dir = docs.appendingPathComponent(ScanConfig.sandboxDirName).path
                let vm = GalleryViewModel(
                    photoRepo: photoRepo, petRepo: petRepo,
                    photoLibrary: photoLibrary, vision: vision,
                    fileStorage: fileStorage, sandboxDir: dir,
                    clipService: clipInferenceService,
                    cursorStore: scanCursorStore,
                    mediaLifecycle: mediaLifecycleService
                )
                vm.loadInitial()
                viewModel = vm
            }
        }
        .navigationTitle("相册")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let vm = viewModel, !vm.photos.isEmpty {
                    Button {
                        vm.startScan()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(vm.isScanning)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                if let vm = viewModel, !vm.photos.isEmpty {
                    Button {
                        vm.toggleMultiSelect()
                    } label: {
                        Image(systemName: vm.isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                }
            }
        }
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
    }

    // MARK: - 内容区

    @ViewBuilder
    private func content(_ vm: GalleryViewModel) -> some View {
        let kind = GalleryPageState.resolveContentKind(
            display: vm.displaySnapshot, filter: vm.filterSnapshot
        )
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
            .tint(Color.milensPrimary)
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
                                .font(.displayMedium)
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

    @ViewBuilder
    private func filterChips(_ vm: GalleryViewModel) -> some View {
        let pets = vm.pets.map { GalleryFilterPet(id: $0.id, name: $0.name) }
        let chips = GalleryFilterLogic.buildChips(pets: pets, selectedPetID: vm.selectedFilter.petID)
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                ForEach(chips) { chip in
                    Button {
                        withAnimation(.easeInOut(duration: Motion.durationFast)) {
                            vm.selectPet(chip.petID)
                        }
                    } label: {
                        Text(chip.title)
                            .font(.bodySecondary.weight(.semibold))
                            .foregroundStyle(chip.isSelected ? Color.milensTextOnActionPrimary : Color.milensTextSecondary)
                            .padding(.horizontal, Spacing.lg)
                            .frame(minHeight: Sizing.touchTarget)
                            .background(chip.isSelected ? Color.milensActionPrimary : Color.milensCard)
                            .overlay {
                                Capsule().stroke(Color.milensBorder, lineWidth: chip.isSelected ? 0 : 0.5)
                            }
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
        Group {
            if vm.isMultiSelectMode {
                Button {
                    vm.toggleSelection(photo.id)
                } label: {
                    PhotoThumbnailCell(photo: photo, isMultiSelect: true,
                                       isSelected: vm.selectedPhotoIDs.contains(photo.id))
                }
                .buttonStyle(.plain)
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
        .background(.ultraThinMaterial)
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
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .matchedGeometryEffect(id: heroID, in: heroNamespace)
            } else {
                ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if isMultiSelect {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.milensPrimary : .white)
                    .padding(4)
            }
            if photo.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.milensPrimary)
                    .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
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
                    .fill(Color(.systemGray5))
                    .overlay(ProgressView().scaleEffect(0.5))
            }
        }
        .task {
            guard image == nil else { return }
            // 本地文件加载——在后台线程解码
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: self.path)
            }.value
            await MainActor.run { self.image = loaded }
        }
    }
}

// MARK: - 扫描完成弹窗

private struct ScanCompleteSheet: View {
    let viewModel: GalleryViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: viewModel.scanFailed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(viewModel.scanFailed ? Color.orange : Color.milensPrimary)

                Text(viewModel.scanFailed ? "扫描未完成" : "扫描完成")
                    .font(.displayMedium)

                Text(viewModel.scanCompleteMessage)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if !viewModel.unassignedPetUris.isEmpty {
                    Button {
                        viewModel.importUnassigned()
                    } label: {
                        Label("导入 \(viewModel.unassignedPetUris.count) 张照片", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.milensPrimary)
                    .disabled(viewModel.isImporting)
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

#Preview {
    NavigationStack {
        GalleryView()
    }
}
