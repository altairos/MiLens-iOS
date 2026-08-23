//  PhotoViewView —— 大图查看（对照 Figma「08·照片详情」#211:306）。
//
//  全屏暗色照片 + 顶部白色圆形按钮（返回/收藏）+ 底部信息 Sheet（日期 + 文楷标题 +
//  元数据 + 拨盘式 CTA + 快捷操作圆）。
//  手势/坐标计算使用 PhotoViewGestureMath 纯函数（缩放钳制、平移钳制、宽高比）。
//  支持：双击缩放、捏合缩放、平移、下滑关闭。

import SwiftUI
import UIKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "PhotoView")

struct PhotoViewView: View {
    let photoID: UUID
    let heroNamespace: Namespace.ID?
    let heroID: UUID?

    init(photoID: UUID, heroNamespace: Namespace.ID? = nil, heroID: UUID? = nil) {
        self.photoID = photoID
        self.heroNamespace = heroNamespace
        self.heroID = heroID
    }

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.photoRepository) private var photoRepo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.proEntitlement) private var entitlement

    @State private var photo: Photo?
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dismissOffset: CGSize = .zero
    @State private var dismissScale: CGFloat = 1
    @State private var backgroundOpacity: CGFloat = 1
    @State private var isDismissing = false
    @State private var showAssignment = false
    @State private var showAddMemorySheet = false
    @State private var shareItem: ShareItem?
    private let timelineAccessStore: any TimelineAccessStore = UserDefaultsTimelineAccessStore()

    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()

                if let image {
                    imageView(image: image, geometry: geo)
                        .gesture(magnificationGesture(geo))
                        .gesture(dragGesture(geo))
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(duration: Motion.durationNormal, bounce: 0.1)) {
                                if scale > 1 {
                                    resetZoom()
                                } else {
                                    scale = doubleTapScale
                                    lastScale = doubleTapScale
                                }
                            }
                        }
                } else {
                    ProgressView()
                        .tint(.white)
                }

                // 顶部渐变（对照 Photo Top Gradient #211:308）
                LinearGradient(
                    colors: [Color.black.opacity(0.5), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // 顶部工具栏（白色圆形按钮）
                topControls
                    .ignoresSafeArea(edges: .top)

                // 底部信息 Sheet（对照 Photo Information Sheet #211:316）
                if photo != nil {
                    VStack(spacing: 0) {
                        Spacer()
                        infoSheet
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAssignment) {
            if let photo {
                PetAssignmentSheet(photos: [photo]) { }
            }
        }
        .sheet(isPresented: $showAddMemorySheet) {
            if let photo {
                let vm = factory.makeTimelineViewModel()
                let pets: [Pet] = (try? factory.allPets()) ?? []
                AddMemorySheet(
                    viewModel: vm,
                    pets: pets,
                    isPro: entitlement.isPro,
                    firstAccessDate: timelineAccessStore.firstAccessDate(now: Date()),
                    prefilledPhotoID: photo.id
                )
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .task {
            await loadData()
        }
    }

    // MARK: - 顶部工具栏（白色圆形按钮，对照 Figma #211:309-313）

    private var topControls: some View {
        HStack(alignment: .top) {
            // 返回按钮
            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 44, height: 44)
                    Image(systemName: "chevron.left")
                        .font(.system(size: Sizing.iconSm, weight: .semibold))
                        .foregroundStyle(Color.milensInk)
                }
            }
            .accessibilityLabel(String(localized: "common.back"))

            Spacer()

            // 收藏按钮
            if let photo {
                Button {
                    // 收藏切换：复用 GalleryView 的 contextMenu 模式
                    toggleFavorite()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 44, height: 44)
                        Image(systemName: photo.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: Sizing.iconSm))
                            .foregroundStyle(photo.isFavorite ? Color.milensActionPrimary : Color.milensInk)
                    }
                }
                // 独立收藏按钮 label：不复用 a11y.gallery.favorite（后者带拼接前导逗号）
                .accessibilityLabel(String(localized: "a11y.photoView.favorite"))
            }
        }
        .padding(.horizontal, 19)
        .padding(.top, 14)
    }

    // MARK: - 底部信息 Sheet（对照 Figma #211:316）

    private var infoSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 日期 + 标题 + 元数据（对照 #211:317-319）
            VStack(alignment: .leading, spacing: 6) {
                Text(dateLabel)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(titleText)
                    .font(.localeDisplayFont(size: 25, relativeTo: .title2))
                    .foregroundStyle(Color.milensTextPrimary)
                Text(metadataText)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, 25)

            // 拨盘式 CTA（对照 Focus Dial #267:285）
            ctaButton
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.lg)

            // 三个快捷操作圆（对照 #211:324-338）
            quickActions
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .background(Color.milensBackground)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, y: -4)
    }

    // MARK: - 拨盘式 CTA（对照 Figma #267:285）

    private var ctaButton: some View {
        Button {
            showAddMemorySheet = true
        } label: {
            HStack {
                Text(String(localized: "photo.detail.addToMemory"))
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensDarkroomText)
                Spacer()
                // 暗色拨盘圆
                ZStack {
                    Circle()
                        .fill(Color.milensDialSurface)
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(Color.milensDarkroomText, lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: Sizing.iconMd, weight: .bold))
                        .foregroundStyle(Color.milensDarkroomText)
                }
            }
            .padding(.leading, 24)
            .padding(.trailing, 7)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.milensActionPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 快捷操作圆（对照 Figma #211:324-338）

    private var quickActions: some View {
        HStack(spacing: 0) {
            quickActionItem(
                icon: "person.crop.circle.badge.plus",
                label: String(localized: "photo.detail.assign")
            ) {
                showAssignment = true
            }
            Spacer()
            quickActionItem(
                icon: "slider.horizontal.3",
                label: String(localized: "photo.detail.editInfo")
            ) {
                // 编辑器入口
            }
            .background(
                NavigationLink(value: Route.editor(photoID: photoID)) { Color.clear }
                    .buttonStyle(.plain)
            )
            Spacer()
            quickActionItem(
                icon: "square.and.arrow.up",
                label: String(localized: "photo.detail.share")
            ) {
                guard let photo else { return }
                shareItem = ShareItem(url: URL(fileURLWithPath: photo.uri))
            }
        }
        .padding(.horizontal, Spacing.pagePad)
    }

    private func quickActionItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.milensGrouped)
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: Sizing.iconMd))
                        .foregroundStyle(Color.milensInk)
                }
                Text(label)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 70)
    }

    // MARK: - 衍生数据

    private var dateLabel: String {
        PhotoViewDisplayLogic.dateLabel(takenAt: photo?.takenAt)
    }

    private var titleText: String {
        PhotoViewDisplayLogic.titleText(note: photo?.note ?? "")
    }

    private var metadataText: String {
        PhotoViewDisplayLogic.metadataText(petName: photo?.pet?.name ?? "")
    }

    private func toggleFavorite() {
        guard let photo else { return }
        let newState = !photo.isFavorite
        do {
            try photoRepo.setFavorite(photo, favorite: newState)
            photo.isFavorite = newState
        } catch {
            logger.error("toggleFavorite: 更新收藏失败（\(error.localizedDescription)）")
        }
    }

    @ViewBuilder
    private func imageView(image: UIImage, geometry geo: GeometryProxy) -> some View {
        let content = Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale * dismissScale)
            .offset(x: offset.width + dismissOffset.width,
                    y: offset.height + dismissOffset.height)

        if let heroNamespace, let heroID {
            content.matchedGeometryEffect(id: heroID, in: heroNamespace)
        } else {
            content
        }
    }

    // MARK: - 手势

    private func magnificationGesture(_ geo: GeometryProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                scale = PhotoViewGestureMath.clampScale(newScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { resetZoom() }
            }
    }

    private func dragGesture(_ geo: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isDismissing else { return }
                if scale > 1 {
                    let maxPan = PhotoViewGestureMath.computeMaxPanOffset(
                        containerWidth: geo.size.width, imageScale: scale
                    )
                    offset = CGSize(
                        width: PhotoViewGestureMath.clampPanOffset(
                            lastOffset.width + value.translation.width, maxPan: maxPan
                        ),
                        height: PhotoViewGestureMath.clampPanOffset(
                            lastOffset.height + value.translation.height, maxPan: maxPan
                        )
                    )
                } else if value.translation.height > 0,
                          abs(value.translation.height) > abs(value.translation.width) {
                    let progress = min(value.translation.height / max(geo.size.height, 1), 1)
                    dismissOffset = CGSize(width: value.translation.width * 0.15,
                                           height: value.translation.height)
                    dismissScale = 1 - progress * 0.12
                    backgroundOpacity = 1 - progress * 0.55
                }
            }
            .onEnded { value in
                guard !isDismissing else { return }
                if scale > 1 {
                    lastOffset = offset
                    return
                }

                let shouldDismiss = value.translation.height > 120
                    && abs(value.translation.height) > abs(value.translation.width)
                if shouldDismiss {
                    isDismissing = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let finalOffset = max(value.translation.height, geo.size.height * 0.35)
                    withAnimation(.easeOut(duration: Motion.durationNormal)) {
                        dismissOffset = CGSize(width: value.translation.width * 0.15,
                                               height: finalOffset)
                        dismissScale = 0.86
                        backgroundOpacity = 0
                    }
                    Task { @MainActor in
                        do {
                            try await Task.sleep(nanoseconds: 260_000_000)
                        } catch {
                            return
                        }
                        dismiss()
                    }
                } else {
                    withAnimation(.spring(duration: Motion.durationNormal, bounce: 0.1)) {
                        dismissOffset = .zero
                        dismissScale = 1
                        backgroundOpacity = 1
                    }
                }
            }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    // MARK: - 数据加载

    @MainActor
    private func loadData() async {
        do {
            photo = try factory.photo(id: photoID)
        } catch {
            photo = nil
            logger.error("loadData: 读取照片记录失败（\(self.photoID)，\(error.localizedDescription)）")
        }
        guard let photo else { return }
        let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
        let loaded = await Task.detached(priority: .utility) {
            UIImage(contentsOfFile: path)
        }.value
        image = loaded
    }
}

#Preview {
    NavigationStack {
        PhotoViewView(photoID: UUID())
    }
}
