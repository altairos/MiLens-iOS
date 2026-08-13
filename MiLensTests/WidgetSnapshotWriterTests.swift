import XCTest
import UIKit
import MiLensKit
@testable import MiLens

/// WidgetSnapshotWriter 缩略图写入竞态测试（P2 修复）。
///
/// 修复前：`isStale()` 检查与 `downsampleAndCopy` 不是原子操作——旧任务通过检查后
/// 开始降采样，新任务可能在此期间写入同名缩略图，旧任务降采样完成后覆盖新结果。
/// 修复后：`downsample` 与文件写入分离，写入前二次检查 `isStale()`，
/// 旧代降采样完成但已被新代取代时不再写磁盘。
final class WidgetSnapshotWriterTests: XCTestCase {

    /// 降采样前通过、降采样后过期 → 缩略图文件不得写入。
    func testCopyThumbnailsSkipsWriteWhenStaleAfterDownsample() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 创建真实 JPEG 源文件（downsample 需要 CGImageSourceCreateWithURL）
        let sourceURL = tempDir.appendingPathComponent("source.jpg")
        try makeTestJPEG(width: 20, height: 20).write(to: sourceURL)

        // staleAfter=2：第 1 次（清理阶段）和第 2 次（降采样前）返回 false，
        // 第 3 次（降采样后、写入前）返回 true → 中止写入。
        let counter = StaleCallCounter(staleAfter: 2)
        let isStale: @Sendable () async -> Bool = { counter.isStale() }

        let sources: [(sourcePath: String, destName: String)] = [
            (sourcePath: sourceURL.path, destName: "thumb-001.jpg")
        ]

        await WidgetSnapshotWriter.copyThumbnails(
            sources, to: tempDir, maxSize: 100, isStale: isStale)

        let thumbDir = tempDir.appendingPathComponent(WidgetSharedConfig.thumbnailsDirName)
        let destURL = thumbDir.appendingPathComponent("thumb-001.jpg")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destURL.path),
            "降采样后代数过期时不得写入缩略图——防止旧任务覆盖新任务结果")
    }

    /// 全程未过期 → 缩略图正常写入。
    func testCopyThumbnailsWritesWhenNotStale() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("source.jpg")
        try makeTestJPEG(width: 20, height: 20).write(to: sourceURL)

        let sources: [(sourcePath: String, destName: String)] = [
            (sourcePath: sourceURL.path, destName: "thumb-002.jpg")
        ]

        await WidgetSnapshotWriter.copyThumbnails(
            sources, to: tempDir, maxSize: 100, isStale: { false })

        let thumbDir = tempDir.appendingPathComponent(WidgetSharedConfig.thumbnailsDirName)
        let destURL = thumbDir.appendingPathComponent("thumb-002.jpg")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: destURL.path),
            "未过期时缩略图应正常写入")
    }

    /// downsample 函数对有效 JPEG 返回非 nil 数据。
    func testDownsampleReturnsDataForValidImage() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("source.jpg")
        try makeTestJPEG(width: 40, height: 30).write(to: sourceURL)

        let data = WidgetSnapshotWriter.downsample(
            sourcePath: sourceURL.path, maxPixelSize: 10)
        XCTAssertNotNil(data, "有效 JPEG 须返回降采样数据")
        XCTAssertTrue((data?.count ?? 0) > 0)
    }

    // MARK: - 辅助

    /// 生成纯色测试 JPEG。
    private func makeTestJPEG(width: Int, height: Int) -> Data {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height))
        let image = renderer.image { ctx in
            UIColor.systemRed.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }
}

/// 线程安全的代数计数器：前 `staleAfter` 次调用返回 false，之后返回 true。
final class StaleCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let staleAfter: Int

    init(staleAfter: Int) { self.staleAfter = staleAfter }

    func isStale() -> Bool {
        lock.lock()
        count += 1
        let result = count > staleAfter
        lock.unlock()
        return result
    }
}
