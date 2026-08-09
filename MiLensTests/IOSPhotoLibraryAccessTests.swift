//  IOSPhotoLibraryAccessTests —— Photos 桥接取消竞态与回调解析测试（评审阻塞项）。
//
//  覆盖三层：
//  1. RequestIDBox 取消墓碑：cancel 先于 set 到达时，晚到的请求 ID 必须被立即取消；
//  2. ImageRequestOutcome 回调解析：cancelled/error/degraded/成功各键的确定性映射；
//  3. 端到端桥接：fake PHImageRequesting 注入 IOSPhotoLibraryAccess，
//     degraded 多回调只恢复一次、任务取消联动 cancelImageRequest。
//
//  测试不触碰真实相册：PHAsset() 为空对象，fake manager 不使用其内部数据。

import XCTest
import Photos
import UIKit
@testable import MiLens

/// fake PHImageManager：记录请求/取消调用，可手动触发回调（桥接测试用）。
private final class FakeImageManager: PHImageRequesting, @unchecked Sendable {

    private(set) var issuedIDs: [PHImageRequestID] = []
    private(set) var cancelledIDs: [PHImageRequestID] = []
    var dataHandler: ((Data?, [AnyHashable: Any]?) -> Void)?
    var imageHandler: ((UIImage?, [AnyHashable: Any]?) -> Void)?
    private var nextID: PHImageRequestID = 1

    func requestImageDataAndOrientation(
        for asset: PHAsset,
        options: PHImageRequestOptions?,
        resultHandler: @escaping (Data?, String?, CGImagePropertyOrientation, [AnyHashable: Any]?) -> Void
    ) -> PHImageRequestID {
        let id = nextID
        nextID += 1
        issuedIDs.append(id)
        dataHandler = { data, info in resultHandler(data, nil, .up, info) }
        return id
    }

    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions?,
        resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void
    ) -> PHImageRequestID {
        let id = nextID
        nextID += 1
        issuedIDs.append(id)
        imageHandler = { image, info in resultHandler(image, info) }
        return id
    }

    func cancelImageRequest(_ requestID: PHImageRequestID) {
        cancelledIDs.append(requestID)
    }
}

final class IOSPhotoLibraryAccessTests: XCTestCase {

    // MARK: - RequestIDBox 取消竞态（评审阻塞项：cancel 先于 set 的乱序）

    /// 取消先于请求发起到达（onCancel 早于 requestImage 返回）：
    /// 取消墓碑必须让晚到的请求 ID 被立即取消，不能留下不可取消的请求。
    func testCancelBeforeSetCancelsNewRequestImmediately() {
        let manager = FakeImageManager()
        let box = RequestIDBox()

        box.cancel(manager: manager)   // 模拟 onCancel 先执行（此时无 ID）
        let wasCancelled = box.set(42, manager: manager)

        XCTAssertTrue(wasCancelled, "取消墓碑应使新 ID 登记时即判定已取消")
        XCTAssertEqual(manager.cancelledIDs, [42], "晚到的请求 ID 必须被立即取消")
    }

    /// 常规路径：请求已发起后取消 → 取消当前 ID。
    func testCancelAfterSetCancelsCurrentRequest() {
        let manager = FakeImageManager()
        let box = RequestIDBox()

        box.set(7, manager: manager)
        box.cancel(manager: manager)

        XCTAssertEqual(manager.cancelledIDs, [7])
    }

    /// 无 ID 时取消只记录墓碑，不产生无效取消调用。
    func testCancelWithoutPendingRequestSetsTombstoneOnly() {
        let manager = FakeImageManager()
        let box = RequestIDBox()

        box.cancel(manager: manager)

        XCTAssertTrue(manager.cancelledIDs.isEmpty, "无 ID 时不应调用 cancelImageRequest")
        // 墓碑仍生效：随后的 set 会被立即取消
        box.set(9, manager: manager)
        XCTAssertEqual(manager.cancelledIDs, [9])
    }

    /// continuation 恢复权只能被消费一次（degraded 多回调场景防二次 resume）。
    func testBeginResumeOnlyOnce() {
        let box = RequestIDBox()

        XCTAssertTrue(box.beginResume())
        XCTAssertFalse(box.beginResume())
        XCTAssertFalse(box.beginResume())
    }

    // MARK: - 回调解析（ImageRequestOutcome 纯逻辑）

    func testOutcomeSuccess() {
        let outcome = ImageRequestOutcome<Data>.resolve(
            value: Data([1]), info: [:], isCancelled: false,
            fallbackError: PhotoLibraryError.imageDataUnavailable("x"))
        guard case .success(let data) = outcome else {
            return XCTFail("应解析为 success")
        }
        XCTAssertEqual(data, Data([1]))
    }

    func testOutcomeCancelledKeyMapsToCancellationError() {
        let outcome = ImageRequestOutcome<Data>.resolve(
            value: Data([1]), info: [PHImageCancelledKey: true], isCancelled: false,
            fallbackError: PhotoLibraryError.imageDataUnavailable("x"))
        guard case .failure(let error) = outcome else {
            return XCTFail("应解析为 failure")
        }
        XCTAssertTrue(error is CancellationError)
    }

    func testOutcomeErrorKeySurfacesError() {
        struct FakeError: Error {}
        let outcome = ImageRequestOutcome<Data>.resolve(
            value: nil, info: [PHImageErrorKey: FakeError()], isCancelled: false,
            fallbackError: PhotoLibraryError.imageDataUnavailable("x"))
        guard case .failure(let error) = outcome else {
            return XCTFail("应解析为 failure")
        }
        XCTAssertTrue(error is FakeError)
    }

    func testOutcomeNilValueFallsBackToError() {
        let outcome = ImageRequestOutcome<Data>.resolve(
            value: nil, info: [:], isCancelled: false,
            fallbackError: PhotoLibraryError.imageDataUnavailable("abc"))
        guard case .failure(let error) = outcome else {
            return XCTFail("应解析为 failure")
        }
        XCTAssertEqual(error as? PhotoLibraryError, .imageDataUnavailable("abc"))
    }

    func testOutcomeDegradedMapsToWaitForFinalFrame() {
        let outcome = ImageRequestOutcome<Data>.resolve(
            value: Data([1]), info: [PHImageResultIsDegradedKey: true], isCancelled: false,
            fallbackError: PhotoLibraryError.imageDataUnavailable("x"))
        guard case .waitForFinalFrame = outcome else {
            return XCTFail("degraded 帧应标记为继续等待")
        }
    }

    // MARK: - 端到端桥接（fake manager 注入）

    private func waitUntil(
        _ condition: @escaping () -> Bool, timeout: TimeInterval = 2
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    func testLoadOriginalDataSuccess() async throws {
        let manager = FakeImageManager()
        let access = IOSPhotoLibraryAccess(manager: manager)
        let payload = Data([0x89, 0x50, 0x4E, 0x47])

        let task = Task { try await access.loadOriginalData(PHAsset()) }
        XCTAssertTrue(await waitUntil { manager.dataHandler != nil })
        manager.dataHandler?(payload, [:])

        let result = try await task.value
        XCTAssertEqual(result, payload)
    }

    func testLoadOriginalDataCancelledKeyThrowsCancellation() async throws {
        let manager = FakeImageManager()
        let access = IOSPhotoLibraryAccess(manager: manager)

        let task = Task { try await access.loadOriginalData(PHAsset()) }
        XCTAssertTrue(await waitUntil { manager.dataHandler != nil })
        manager.dataHandler?(nil, [PHImageCancelledKey: true])

        do {
            _ = try await task.value
            XCTFail("应抛出 CancellationError")
        } catch is CancellationError {
            // 预期
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
    }

    /// degraded 中间帧不恢复 continuation，最终高清帧到达后才返回（防提前完成）。
    func testLoadOriginalDataDegradedThenFinal() async throws {
        let manager = FakeImageManager()
        let access = IOSPhotoLibraryAccess(manager: manager)
        let payload = Data([1, 2, 3])

        let task = Task { try await access.loadOriginalData(PHAsset()) }
        XCTAssertTrue(await waitUntil { manager.dataHandler != nil })
        manager.dataHandler?(Data([9]), [PHImageResultIsDegradedKey: true])
        // 短暂让出后任务不应已完成（degraded 帧被忽略）
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(task.isCancelled, false)

        manager.dataHandler?(payload, [:])
        let result = try await task.value
        XCTAssertEqual(result, payload)
    }

    /// 任务取消：onCancel 必须联动 cancelImageRequest（iCloud 下载随扫描取消停止）。
    func testCancelledTaskCancelsPendingRequest() async throws {
        let manager = FakeImageManager()
        let access = IOSPhotoLibraryAccess(manager: manager)

        let task = Task { try await access.loadOriginalData(PHAsset()) }
        XCTAssertTrue(await waitUntil { manager.dataHandler != nil })
        let issued = manager.issuedIDs
        XCTAssertFalse(issued.isEmpty)

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("取消后应抛出 CancellationError")
        } catch is CancellationError {
            // 预期
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
        XCTAssertEqual(manager.cancelledIDs, issued, "任务取消必须取消已发起的图片请求")
    }

    /// 缩放图桥接：degraded 忽略 + 最终帧编码为 JPEG 返回。
    func testLoadScaledImageReturnsJPEG() async throws {
        let manager = FakeImageManager()
        let access = IOSPhotoLibraryAccess(manager: manager)
        let source = makeImage(width: 8, height: 8)

        let task = Task { try await access.loadScaledImage(PHAsset(), maxDimension: 16) }
        XCTAssertTrue(await waitUntil { manager.imageHandler != nil })
        manager.imageHandler?(source, [PHImageResultIsDegradedKey: true])
        manager.imageHandler?(source, [:])

        let jpeg = try await task.value
        XCTAssertTrue(jpeg.starts(with: [0xFF, 0xD8]), "应返回 JPEG 编码数据")
    }

    /// 缩放图 error 键直接抛出，不降级为成功。
    func testLoadScaledImageErrorKeyThrows() async throws {
        struct FakeError: Error {}
        let manager = FakeImageManager()
        let access = IOSPhotoLibraryAccess(manager: manager)

        let task = Task { try await access.loadScaledImage(PHAsset(), maxDimension: 16) }
        XCTAssertTrue(await waitUntil { manager.imageHandler != nil })
        manager.imageHandler?(nil, [PHImageErrorKey: FakeError()])

        do {
            _ = try await task.value
            XCTFail("应抛出 FakeError")
        } catch is FakeError {
            // 预期
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
    }

    // MARK: - 工具

    private func makeImage(width: Int, height: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
