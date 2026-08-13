//  AvatarCropSheet —— 头像裁切 Sheet（对应源端 pages/AvatarCropPage.ets）。
//
//  全屏暗色背景 + 图片预览（手势缩放/平移）+ 中心圆形裁剪框。
//  用户确定后根据缩放/偏移计算裁剪区域，裁剪 + 缩放到 256×256 JPEG 保存到沙盒 avatars 目录。
//
//  裁剪坐标计算见 AvatarCropMath（纯函数，可单测）。
//  iOS 架构差异：源端 PixelMap.crop()+scale() → iOS CGImage.cropping(to:)+CGContext 重绘。

import SwiftUI
import UIKit
import PhotosUI
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "AvatarCrop")

/// 头像裁切 Sheet。
///
/// 用法：`.sheet(isPresented:) { AvatarCropSheet(image: img) { path in ... } }`
struct AvatarCropSheet: View {
    let image: UIImage
    var onCropped: (String) -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isSaving = false
    @State private var errorMessage = ""

    private let maxPinchScale: CGFloat = 2.5
    private let cropSize: CGFloat = 256

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                // 裁切预览区
                cropPreview
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)

                Text(String(localized: "avatar.crop.hint"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                // 底部按钮
                HStack(spacing: Spacing.md) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                        onCancel()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.15))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button(String(localized: "common.confirm")) {
                        performCrop()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.milensActionPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(isSaving)
                }
                .padding(.horizontal, Spacing.pagePad)
                .padding(.bottom, Spacing.xxl)
            }

            if isSaving {
                ProgressView()
                    .tint(.white)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.milensDanger.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 100)
            }
        }
    }

    // MARK: - 裁切预览

    private var cropPreview: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                // 底层图片（带手势缩放/平移）
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .scaleEffect(scale)
                    .offset(offset)

                // 暗色遮罩
                Color.black.opacity(0.45)

                // 中心圆形亮区（显示裁剪区域）
                Circle()
                    .frame(width: size * 0.83, height: size * 0.83)
                    .blendMode(.destinationOut)
                    .overlay(
                        // 圆形亮区内同步显示图片（与底层一致的变换）
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .scaleEffect(scale)
                            .offset(offset)
                            .clipShape(Circle().inset(by: -(size * 0.085)))
                            .frame(width: size * 0.83, height: size * 0.83)
                            .clipShape(Circle())
                    )

                // 圆形裁剪框边框
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: size * 0.83, height: size * 0.83)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .gesture(magnificationGesture(size: size))
            .gesture(dragGesture(size: size))
        }
    }

    // MARK: - 手势

    private func magnificationGesture(size: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                scale = min(max(1.0, newScale), maxPinchScale)
            }
            .onEnded { _ in
                lastScale = scale
                let clamped = AvatarCropMath.clampOffset(
                    offset: AvatarCropOffset(x: Double(offset.width), y: Double(offset.height)),
                    scale: Double(scale), containerSize: Double(size))
                offset = CGSize(width: clamped.x, height: clamped.y)
            }
    }

    private func dragGesture(size: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let raw = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                let clamped = AvatarCropMath.clampOffset(
                    offset: AvatarCropOffset(x: Double(raw.width), y: Double(raw.height)),
                    scale: Double(scale), containerSize: Double(size))
                offset = CGSize(width: clamped.x, height: clamped.y)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    // MARK: - 执行裁切

    private func performCrop() {
        isSaving = true
        errorMessage = ""

        let containerSize: CGFloat = 320
        let cropResult = AvatarCropMath.computeCropRect(
            imageSize: AvatarCropSize(width: Double(image.size.width), height: Double(image.size.height)),
            containerSize: Double(containerSize),
            scale: Double(scale),
            offset: AvatarCropOffset(x: Double(offset.width), y: Double(offset.height)),
            circleRatio: 0.83
        )

        guard let cropped = AvatarCropMath.cropAndResize(
            image: image, cropRect: cropResult, targetSize: cropSize
        ) else {
            errorMessage = String(localized: "avatar.crop.failed")
            isSaving = false
            return
        }

        // 保存到沙盒 avatars 目录
        let path = saveToSandbox(cropped: cropped)
        if let path {
            dismiss()
            onCropped(path)
        }
        isSaving = false
    }

    /// 保存裁切结果到 Documents/MiPhotos/Avatars（与编辑产物同分区，允许备份）。
    private func saveToSandbox(cropped: UIImage) -> String? {
        guard let jpegData = cropped.jpegData(compressionQuality: 0.9) else {
            errorMessage = String(localized: "avatar.crop.failed")
            return nil
        }
        let dir = URL.documentsDirectory
            .appendingPathComponent(ScanConfig.sandboxDirName)
            .appendingPathComponent("Avatars")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("创建 avatars 目录失败（\(error.localizedDescription)）")
            errorMessage = String(localized: "avatar.crop.failed")
            return nil
        }
        let fileName = "avatar_\(Int(Date().timeIntervalSince1970)).jpg"
        let fileURL = dir.appendingPathComponent(fileName)
        do {
            try jpegData.write(to: fileURL)
            return fileURL.path
        } catch {
            logger.error("保存头像失败（\(error.localizedDescription)）")
            errorMessage = String(localized: "avatar.crop.failed")
            return nil
        }
    }
}
