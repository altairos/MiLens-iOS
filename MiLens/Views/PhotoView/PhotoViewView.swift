//  PhotoViewView —— 大图查看（对应源端 pages/PhotoViewPage.ets）。
//  手势/坐标计算使用 PhotoViewGestureMath 纯函数（缩放钳制、平移钳制、宽高比）。
//  支持：双击缩放、捏合缩放、平移。

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
    @Environment(\.dismiss) private var dismiss

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
                            withAnimation(.spring(duration: 0.3)) {
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
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    NavigationLink(value: Route.editor(photoID: photoID)) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel(String(localized: "a11y.photoView.edit"))
                    if let photo {
                        NavigationLink(value: Route.beadPattern(photoID: photo.id)) {
                            Image(systemName: "square.grid.3x3.fill")
                        }
                        .accessibilityLabel(String(localized: "a11y.bead.generate"))
                    }
                }
            }
        }
        .task {
            await loadData()
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
                    // 未放大时，向下拖动代表关闭；水平/向上移动不改变页面位置。
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
                            return  // 任务被取消（视图已离开）
                        }
                        dismiss()
                    }
                } else {
                    withAnimation(.spring(duration: Motion.durationNormal)) {
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
