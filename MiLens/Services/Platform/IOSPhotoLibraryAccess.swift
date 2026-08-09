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

/// PHImageManager 最小适配协议（评审阻塞项：注入可测试的 Photos 请求适配层）。
/// 方法签名与 PHImageManager 公开 API 一一对应；IOSPhotoLibraryAccess 依赖此协议
/// 而非具体类，测试可注入 fake 覆盖取消竞态/回调解析路径。
protocol PHImageRequesting: Sendable {
    func requestImageDataAndOrientation(
        for asset: PHAsset,
        options: PHImageRequestOptions?,
        resultHandler: @escaping (Data?, String?, CGImagePropertyOrientation, [AnyHashable: Any]?) -> Void
    ) -> PHImageRequestID

    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions?,
        resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void
    ) -> PHImageRequestID

    func cancelImageRequest(_ requestID: PHImageRequestID)
}

/// PHImageManager 是线程安全的（Apple 文档声明可在任意线程调用 request/cancel），
/// 显式声明 @unchecked Sendable 使其可经协议注入（理由同文件内其它 @unchecked）。
extension PHImageManager: @unchecked Sendable, PHImageRequesting {}

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

    /// 图片请求适配器（默认真实 PHImageManager；测试注入 fake）。
    private let manager: any PHImageRequesting

    init(manager: any PHImageRequesting = PHImageManager.default()) {
        self.manager = manager
    }

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
                fileSize: 0,
                displayName: displayName(of: asset)
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
            fileSize: 0,
            displayName: displayName(of: asset)
        )
    }

    /// 公开 API 读取文件名（PHAssetResource.originalFilename），不依赖 KVC 非公开字段。
    private func displayName(of asset: PHAsset) -> String {
        PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
    }

    // 注意：PHAssetResource 无公开 fileSize API，fileSize 字段恒为 0——
    // 仅辅助展示/排序，ImportService 以实际导入数据大小兜底（诚实标注）。

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
    /// 完整桥接：取消/错误经 info 键识别、continuation 只恢复一次、
    /// 任务取消时 cancelImageRequest（iCloud 下载请求随之停止）。
    /// internal 供桥接单测（fake manager + 空 PHAsset 构造）。
    func loadOriginalData(_ asset: PHAsset) async throws -> Data {
        let box = RequestIDBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // 先登记取消恢复：任务取消时主动 resume continuation（CancellationError），
                // 不依赖 PHImageManager 必然回调；与结果回调共用 beginResume() 单次恢复权，
                // 谁先到都不影响正确性（防二次 resume 崩溃）。
                box.registerCancelResume {
                    Self.resumeCancellation(box, continuation)
                }
                box.set(
                    manager.requestImageDataAndOrientation(
                        for: asset, options: nil
                    ) { data, _, _, info in
                        let outcome = ImageRequestOutcome<Data>.resolve(
                            value: data,
                            info: info,
                            // 回调可能不在原 Task 上下文执行，isCancelled 仅作额外检查；
                            // 取消语义由 RequestIDBox 取消墓碑 + 取消恢复保证（评审阻塞项）。
                            isCancelled: Task.isCancelled,
                            fallbackError: PhotoLibraryError.imageDataUnavailable(asset.localIdentifier)
                        )
                        Self.resumeIfNeeded(box, continuation, outcome)
                    },
                    manager: manager
                )
            }
        } onCancel: {
            box.cancel(manager: manager)
        }
    }

    /// 缩放图数据（AI 检测用）：requestImage 生成缩略图后编码为 JPEG。
    /// 完整桥接：忽略 degraded 中间帧（等最终高清）、取消/错误经 info 键识别、
    /// continuation 只恢复一次、任务取消时 cancelImageRequest。
    /// internal 供桥接单测（fake manager + 空 PHAsset 构造）。
    func loadScaledImage(_ asset: PHAsset, maxDimension: Int) async throws -> Data {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        let targetSize = CGSize(width: maxDimension, height: maxDimension)

        let box = RequestIDBox()
        let image: UIImage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // 先登记取消恢复：任务取消时主动 resume continuation（CancellationError），
                // 不依赖 PHImageManager 必然回调；与结果回调共用 beginResume() 单次恢复权，
                // 谁先到都不影响正确性（防二次 resume 崩溃）。
                box.registerCancelResume {
                    Self.resumeCancellation(box, continuation)
                }
                box.set(
                    manager.requestImage(
                        for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
                    ) { image, info in
                        let outcome = ImageRequestOutcome<UIImage>.resolve(
                            value: image,
                            info: info,
                            isCancelled: Task.isCancelled,
                            fallbackError: PhotoLibraryError.imageDataUnavailable(asset.localIdentifier)
                        )
                        Self.resumeIfNeeded(box, continuation, outcome)
                    },
                    manager: manager
                )
            }
        } onCancel: {
            box.cancel(manager: manager)
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw PhotoLibraryError.imageDataUnavailable(asset.localIdentifier)
        }
        return jpeg
    }

    /// 取消恢复：任务取消时把 continuation resume 为 CancellationError。
    /// 与结果回调共用 beginResume() 单次恢复权，二者谁先到都只恢复一次（防二次 resume）。
    /// static：不捕获 self，闭包保持值捕获（Sendable 干净）。
    private static func resumeCancellation<Value>(
        _ box: RequestIDBox,
        _ continuation: CheckedContinuation<Value, Error>
    ) {
        guard box.beginResume() else { return }
        continuation.resume(throwing: CancellationError())
    }

    /// continuation 单次恢复：degraded 中间帧不消费恢复权（继续等最终帧），
    /// 其余结果只恢复一次（PHImageManager 可能多回调，防二次 resume 崩溃）。
    /// static：不捕获 self，回调闭包保持值捕获（Sendable 干净）。
    private static func resumeIfNeeded<Value>(
        _ box: RequestIDBox,
        _ continuation: CheckedContinuation<Value, Error>,
        _ outcome: ImageRequestOutcome<Value>
    ) {
        if case .waitForFinalFrame = outcome { return }
        guard box.beginResume() else { return }
        switch outcome {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        case .waitForFinalFrame: break
        }
    }
}

/// 图片请求回调解析（纯逻辑，internal 供单测）：把 PHImageManager 的回调值与
/// info 字典解析为确定结果。判断顺序与回调约定一致：取消 → 错误 → 无值 → degraded。
enum ImageRequestOutcome<Value> {
    case success(Value)
    case failure(Error)
    /// degraded 中间帧：忽略，继续等待最终高清帧（不消费 continuation 恢复权）。
    case waitForFinalFrame

    static func resolve(
        value: Value?,
        info: [AnyHashable: Any]?,
        isCancelled: Bool,
        fallbackError: Error
    ) -> ImageRequestOutcome<Value> {
        if isCancelled { return .failure(CancellationError()) }
        if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
            return .failure(CancellationError())
        }
        if let error = info?[PHImageErrorKey] as? Error {
            return .failure(error)
        }
        guard let value else { return .failure(fallbackError) }
        if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
            return .waitForFinalFrame
        }
        return .success(value)
    }
}

/// 请求 ID 传递盒：onCancel 可能先于 request 发起执行（此时无 ID 可取消），
/// 由「取消墓碑」兜底——set 时若取消已到达则**立即取消新 ID**，不留不可取消的请求
/// （评审阻塞项）；id/isCancelled/resumed 的读写以 NSLock 保护（单段临界区，无嵌套）。
/// 取消时还须主动恢复 continuation（系统/测试 fake 不保证回调），否则任务永久挂起。
/// internal 供取消竞态单测。
final class RequestIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var id: PHImageRequestID = PHInvalidImageRequestID
    private var isCancelled = false
    private var resumed = false
    /// 取消时执行的 continuation 恢复闭包（由调用方拿到 continuation 后注册）。
    private var onCancelResume: (() -> Void)?

    /// 登记新请求 ID；若取消已先到达，立即取消该 ID 并返回 true（测试可断言）。
    @discardableResult
    func set(_ newID: PHImageRequestID, manager: any PHImageRequesting) -> Bool {
        lock.lock()
        let cancelled = isCancelled
        if !cancelled {
            id = newID
        }
        lock.unlock()
        if cancelled {
            manager.cancelImageRequest(newID)
        }
        return cancelled
    }

    /// 登记取消时的 continuation 恢复动作。
    /// 若取消已先到（墓碑已置位），立即执行该动作（保证 continuation 必被恢复，
    /// 不依赖 PHImageManager 回调，否则 fake/极端时序下任务永久挂起）。
    func registerCancelResume(_ action: @escaping () -> Void) {
        lock.lock()
        let alreadyCancelled = isCancelled
        if !alreadyCancelled {
            onCancelResume = action
        }
        lock.unlock()
        if alreadyCancelled {
            action()
        }
    }

    /// 取消当前请求并记录取消墓碑（后续 set 的新 ID 会被立即取消）；
    /// 同时执行取消恢复——不依赖 PHImageManager 必然回调 PHImageCancelledKey
    /// （真实系统在极端时序、fake manager 不回调时都会导致任务永久挂起）。
    func cancel(manager: any PHImageRequesting) {
        lock.lock()
        isCancelled = true
        let current = id
        let resume = onCancelResume
        onCancelResume = nil
        lock.unlock()
        if current != PHInvalidImageRequestID {
            manager.cancelImageRequest(current)
        }
        // 先取消系统请求（停止 iCloud 下载等），再恢复 continuation；
        // resumeIfNeeded 经 beginResume() 与结果回调互斥，二者谁先到均安全。
        resume?()
    }

    /// continuation 单次恢复判定（锁保护，多回调/多线程安全）。
    func beginResume() -> Bool {
        lock.lock()
        if resumed {
            lock.unlock()
            return false
        }
        resumed = true
        lock.unlock()
        return true
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
