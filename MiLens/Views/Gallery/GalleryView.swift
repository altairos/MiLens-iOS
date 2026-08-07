//  GalleryView —— 相册网格视图（对应源端 pages/GalleryPage.ets）。
//  LazyVGrid 虚拟化 + 分页加载 + 扫描入口 + 扫描完成弹窗。
//  内容区渲染分支由 GalleryPageState.resolveContentKind 决定。

import SwiftUI

struct GalleryView: View {
    @Environment(\.photoRepository) private var photoRepo
    @Environment(\.petRepository) private var petRepo
    @Environment(\.photoLibraryAccess) private var photoLibrary
    @Environment(\.visionService) private var vision
    @Environment(\.fileStorage) private var fileStorage

    @State private var viewModel: GalleryViewModel?
    @State private var navigationPath = NavigationPath()

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
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let dir = docs.appendingPathComponent(ScanConfig.sandboxDirName).path
                let vm = GalleryViewModel(
                    photoRepo: photoRepo, petRepo: petRepo,
                    photoLibrary: photoLibrary, vision: vision,
                    fileStorage: fileStorage, sandboxDir: dir
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
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(vm.photos.enumerated()), id: \.element.id) { index, photo in
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
                            NavigationLink(value: Route.photoView(photoID: photo.id)) {
                                PhotoThumbnailCell(photo: photo, isMultiSelect: false, isSelected: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onAppear {
                        // 分页：最后 10 个 item 出现时加载更多
                        if index >= vm.photos.count - 10 {
                            vm.loadMore()
                        }
                    }
                }
            }
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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.milensPrimary)

                Text("扫描完成")
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
