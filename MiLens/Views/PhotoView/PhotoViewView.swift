//  PhotoViewView —— 大图查看（对应源端 pages/PhotoViewPage.ets）。
//  手势/坐标计算使用 PhotoViewGestureMath 纯函数（缩放钳制、平移钳制、宽高比）。
//  支持：双击缩放、捏合缩放、平移。

import SwiftUI

struct PhotoViewView: View {
    let photoID: UUID

    @Environment(\.photoRepository) private var photoRepo
    @Environment(\.dismiss) private var dismiss

    @State private var photo: Photo?
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
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
        .task {
            await loadData()
        }
    }

    // MARK: - 手势

    private func magnificationGesture(_ geo: GeometryProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value
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
                guard scale > 1 else { return }
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
            }
            .onEnded { _ in
                lastOffset = offset
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
        photo = try? photoRepo.getPhoto(id: photoID)
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
