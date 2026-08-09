//  IOSPhotoLibraryAccess —— PhotoLibraryAccess 的 Photos 框架真实实现
//  （对应源端 adapters/MediaAccessImpl，补 P2 待办）。
//
//  用 PHAsset / PHFetchOptions / PHImageManager 实现流式遍历、元数据查询、
//  图片加载与授权管理。PHImageManager 回调经 withCheckedContinuation 桥接为 async。
//  DESIGN.md §9 平台适配层：业务层只依赖协议，本文件是唯一直接接触 Photos 的地方。

import Foundation
import Photos
import UIKit
import MiLensKit

/// 照片库授权状态 → iOS 枚举映射（对应源端 PermissionHelper）。
private extension PHAuthorizationStatus {
    var milensStatus: PhotoLibraryAuthorizationStatus {
        switch self {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .limited: return .limited
        case .authorized: return .authorized
        @unknown default: return .denied
        }
    }
}

final class IOSPhotoLibraryAccess: PhotoLibraryAccess, @unchecked Sendable {

    // MARK: - 授权

    func authorizationStatus() async -> PhotoLibraryAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite).milensStatus
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite).milensStatus
    }

    // MARK: - 流式遍历（对应源端 streamPhotoAssets）

    func streamPhotos(
        _ consumer: @escaping (PhotoAssetMetadata) async throws -> Bool
    ) async throws -> Int {
        // 权限不足时不抛错，返回 0（扫描结果为空，由上层引导授权）
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .denied,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) != .restricted,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined else {
            return 0
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)

        var visited = 0
        for index in 0..<fetchResult.count {
            let asset = fetchResult.object(at: index)
            // dateAdded：iOS 无公开「加入相册时间」API，以 creationDate 近似填充
            // （诚实标注，增量扫描游标按此字段过滤，见 ScanCursorStore）。
            let metadata = PhotoAssetMetadata(
                identifier: asset.localIdentifier,
                dateTaken: asset.creationDate,
                dateAdded: asset.creationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                fileSize: fileSize(of: asset),
                displayName: asset.value(forKey: "filename") as? String ?? ""
            )
            visited += 1
            let shouldContinue = try await consumer(metadata)
            if !shouldContinue { break }
        }
        return visited
    }

    // MARK: - 计数

    func photoCount() async throws -> Int {
        PHAsset.fetchAssets(with: .image, options: nil).count
    }

    // MARK: - 元数据查询

    func metadata(forIdentifier identifier: String) async throws -> PhotoAssetMetadata? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        // dateAdded：iOS 无公开「加入相册时间」API，以 creationDate 近似填充（诚实标注）。
        return PhotoAssetMetadata(
            identifier: asset.localIdentifier,
            dateTaken: asset.creationDate,
            dateAdded: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            fileSize: fileSize(of: asset),
            displayName: asset.value(forKey: "filename") as? String ?? ""
        )
    }

    /// PHAsset 文件大小（字节）。PHAssetResource 无公开 fileSize 属性，经 KVC 读取；
    /// 取不到返回 0（仅辅助展示/去重，ImportService 会以实际数据大小兜底）。
    private func fileSize(of asset: PHAsset) -> Int64 {
        guard let resource = PHAssetResource.assetResources(for: asset).first,
              let size = resource.value(forKey: "fileSize") as? NSNumber else { return 0 }
        return size.int64Value
    }

    // MARK: - 图片数据加载

    func loadImageData(forIdentifier identifier: String, maxDimension: Int) async throws -> Data {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else {
            throw PhotoLibraryError.assetNotFound(identifier)
        }
        if maxDimension > 0 {
            return try await loadScaledImage(asset, maxDimension: maxDimension)
        }
        return try await loadOriginalData(asset)
    }

    /// 原图数据（导入用）：requestImageDataAndOrientation 直接取编码数据。
    private func loadOriginalData(_ asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: nil) { data, _, _, _ in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.imageDataUnavailable(asset.localIdentifier))
                }
            }
        }
    }

    /// 缩放图数据（AI 检测用）：requestImage 生成缩略图后编码为 JPEG。
    private func loadScaledImage(_ asset: PHAsset, maxDimension: Int) async throws -> Data {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        let targetSize = CGSize(width: maxDimension, height: maxDimension)

        let image = try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
            ) { image, _ in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.imageDataUnavailable(asset.localIdentifier))
                }
            }
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw PhotoLibraryError.imageDataUnavailable(asset.localIdentifier)
        }
        return jpeg
    }
}

/// 照片库加载错误（业务层可据此降级/提示）。
enum PhotoLibraryError: LocalizedError, Equatable {
    case assetNotFound(String)
    case imageDataUnavailable(String)

    var errorDescription: String? {
        switch self {
        // L5：描述中不落完整 localIdentifier（日志/用户可见面均只保留前缀）
        case .assetNotFound(let id): return "未找到照片资产：\(AppErrorHandler.redactIdentifier(id))"
        case .imageDataUnavailable(let id): return "照片数据加载失败：\(AppErrorHandler.redactIdentifier(id))"
        }
    }
}
