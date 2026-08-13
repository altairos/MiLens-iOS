//  RedPacketCutoutConfirmView —— 抠图确认页（对应 Figma #2 Red Packet / Cutout Confirm · Refined）。
//
//  透明棋盘格背景 + 抠图预览 + 主体状态卡（抠图状态/下一步）+ 工具轨（抠图/重试/换图）。
//  用户确认抠图后进入工作室。失败不伪装，可重试或换图。

import SwiftUI
import UIKit
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "RedPacketCutout")

struct RedPacketCutoutConfirmView: View {
    let templateID: String
    let photoID: UUID
    let petID: UUID?

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.visionService) private var vision
    @Environment(\.dismiss) private var dismiss

    @State private var sourceImage: UIImage?
    @State private var cutoutImage: UIImage?
    @State private var phase: CutoutPhase = .loading
    @State private var hasNavigated = false

    enum CutoutPhase: Equatable {
        case loading       // 正在加载原图
        case processing    // 正在抠图
        case applied       // 抠图成功
        case error         // 抠图失败
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "redpacket.cutout.confirmTitle")) {
                dismiss()
            } trailing: {
                Button {
                    proceedToWorkshop()
                } label: {
                    Text(String(localized: "redpacket.cutout.continue"))
                        .font(.editorialMetadata)
                        .foregroundStyle(phase == .applied ? Color.milensActionPrimary : Color.milensTextSecondary.opacity(0.3))
                }
                .disabled(phase != .applied)
            }

            // 抠图画布
            cutoutCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底部控制面板
            if phase != .loading {
                bottomPanel
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $hasNavigated) {
            RedPacketWorkshopView(
                templateID: templateID,
                photoID: photoID,
                petID: petID,
                skipAutoCutout: true
            )
        }
        .task { await loadAndCutout() }
    }

    // MARK: - 抠图画布

    private var cutoutCanvas: some View {
        GeometryReader { geo in
            let canvasW = min(geo.size.width - 48, 342.0)
            let canvasH = canvasW * (Double(WeChatRedPacketSpec.coverImageHeight) / Double(WeChatRedPacketSpec.coverImageWidth))
            ZStack {
                // 透明棋盘格背景
                transparencyGrid
                    .frame(width: canvasW, height: canvasH)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // 抠图预览
                switch phase {
                case .loading:
                    ProgressView()
                        .tint(Color.milensActionPrimary)
                case .processing:
                    ProgressView()
                        .tint(Color.milensActionPrimary)
                        .scaleEffect(1.2)
                case .applied:
                    if let cutout = cutoutImage {
                        Image(uiImage: cutout)
                            .resizable()
                            .scaledToFit()
                            .frame(width: canvasW, height: canvasH)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                            .transition(.opacity)
                    }
                case .error:
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.milensWarning)
                        Text(String(localized: "redpacket.cutout.failed"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Spacing.pagePad)
    }

    // MARK: - 透明棋盘格

    private var transparencyGrid: some View {
        Canvas { context, size in
            let cellSize: CGFloat = 12
            let cols = Int(size.width / cellSize) + 1
            let rows = Int(size.height / cellSize) + 1
            for row in 0..<rows {
                for col in 0..<cols {
                    let isEven = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isEven ? Color(white: 0.92) : Color(white: 0.98))
                    )
                }
            }
        }
    }

    // MARK: - 底部控制面板

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // 铜色索引条
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 64, height: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Spacing.pagePad)

            // 状态卡
            HStack(spacing: 0) {
                // 左：抠图状态
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "redpacket.cutout.status"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.milensTextSecondary)
                    Text(statusText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(statusColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 32)

                // 右：下一步
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "redpacket.cutout.nextStep"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.milensTextSecondary)
                    Text(String(localized: "redpacket.cutout.canEdit"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(phase == .applied ? Color.milensActionPrimary : Color.milensTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.vertical, Spacing.sm)

            // 工具轨
            HStack(spacing: 0) {
                toolTab(
                    icon: "person.crop.square",
                    label: String(localized: "redpacket.cutout.tool.cutout"),
                    isSelected: true
                ) {
                    Task { await performCutout() }
                }
                toolTab(
                    icon: "arrow.clockwise",
                    label: String(localized: "redpacket.cutout.tool.retry"),
                    isSelected: false
                ) {
                    Task { await performCutout() }
                }
                toolTab(
                    icon: "photo",
                    label: String(localized: "redpacket.cutout.tool.changePhoto"),
                    isSelected: false
                ) {
                    dismiss()
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, Spacing.sm)
        }
        .background(Color.milensSealSurface)
    }

    // MARK: - 工具按钮

    private func toolTab(icon: String, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                if isSelected {
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 40, height: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 状态文本/颜色

    private var statusText: String {
        switch phase {
        case .loading: return String(localized: "redpacket.cutout.loading")
        case .processing: return String(localized: "redpacket.cutout.processing")
        case .applied: return String(localized: "redpacket.cutout.subjectSeparated")
        case .error: return String(localized: "redpacket.cutout.failedShort")
        }
    }

    private var statusColor: Color {
        switch phase {
        case .applied: return .milensActionPrimary
        case .error: return .milensDanger
        default: return .milensTextSecondary
        }
    }

    // MARK: - 动作

    private func proceedToWorkshop() {
        guard phase == .applied else { return }
        hasNavigated = true
    }

    // MARK: - 数据

    @MainActor
    private func loadAndCutout() async {
        phase = .loading
        do {
            guard let photo = try factory.photo(id: photoID) else {
                logger.error("loadAndCutout: 照片不存在")
                phase = .error
                return
            }
            let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: path)
            }.value
            guard let loaded else {
                logger.error("loadAndCutout: 照片解码失败")
                phase = .error
                return
            }
            sourceImage = loaded
            await performCutout()
        } catch {
            logger.error("loadAndCutout: \(error.localizedDescription)")
            phase = .error
        }
    }

    @MainActor
    private func performCutout() async {
        guard let image = sourceImage,
              let data = image.jpegData(compressionQuality: 0.9) else {
            phase = .error
            return
        }
        phase = .processing

        // Vision 分割
        let result: SegmentationResult?
        do {
            result = try await vision.segmentSubject(in: data)
        } catch {
            logger.error("performCutout: 分割失败 \(error.localizedDescription)")
            result = nil
        }

        guard let seg = result, seg.bboxWidth > 0, seg.bboxHeight > 0,
              let cgImage = image.cgImage else {
            // 失败即 error，不用中心裁切伪装（诚实标注）
            phase = .error
            return
        }

        // 应用蒙版
        guard let cutout = applyCutoutMask(
            cgImage: cgImage, mask: [UInt8](seg.mask),
            bboxX: Int(seg.bboxX), bboxY: Int(seg.bboxY),
            bboxWidth: seg.bboxWidth, bboxHeight: seg.bboxHeight
        ) else {
            phase = .error
            return
        }

        withAnimation(.easeOut(duration: 0.25)) {
            cutoutImage = cutout
            phase = .applied
        }
    }

    /// 把 bbox 局部 mask 平铺到全图，生成透明抠图。
    private func applyCutoutMask(
        cgImage: CGImage, mask: [UInt8],
        bboxX: Int, bboxY: Int, bboxWidth: Int, bboxHeight: Int
    ) -> UIImage? {
        let imgW = cgImage.width
        let imgH = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = imgW * bytesPerPixel

        guard let context = CGContext(
            data: nil, width: imgW, height: imgH,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))

        guard let pixelData = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        for y in 0..<bboxHeight {
            let dstY = bboxY + y
            guard dstY >= 0, dstY < imgH else { continue }
            for x in 0..<bboxWidth {
                let dstX = bboxX + x
                guard dstX >= 0, dstX < imgW else { continue }
                let maskIdx = y * bboxWidth + x
                guard maskIdx < mask.count else { continue }
                let alpha = mask[maskIdx]
                let pixelIdx = (dstY * imgW + dstX) * bytesPerPixel
                pixelData[pixelIdx + 3] = min(pixelData[pixelIdx + 3], alpha)
            }
        }

        guard let outputCG = context.makeImage() else { return nil }
        return UIImage(cgImage: outputCG)
    }
}
