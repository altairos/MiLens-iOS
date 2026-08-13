//  AnalysisExecutor —— 受限并发的图像分析后台执行器（P1 性能）。
//
//  所有 CPU 密集段（JPEG 解码、Laplacian、pHash、VNRequest、CLIP 预处理）
//  经本执行器运行，保证像素计算不阻塞 MainActor，同时限制并发防止 CPU 过载
//  （5000 张图库扫描/评分场景）。
//
//  用法：QualityScorer / ScanService 把「读文件 + 解码 + 计算」整体放入
//  `executor.run`，只把 SwiftData 读写与进度状态留在 MainActor。
//
//  取消语义（P1 修复）：
//  - 任务在队列中等待时被取消 → 立即从等待队列移除并抛 CancellationError，
//    不再占用后续槽位执行（旧行为：被取消的等待者仍会在获得槽位后执行）。
//  - 获得槽位后检查取消状态 → 若已取消则立即释放槽位，不执行操作。
//  - withTaskCancellationHandler 确保取消信号能跨 actor 边界传递到等待队列。

import Foundation

actor AnalysisExecutor {

    /// 最大并发数（internal 只读——调用方按此分批提交任务）。
    let maxConcurrent: Int
    private var inFlight = 0

    /// 等待者：(唯一令牌, 可取消的 throwing continuation)。
    /// 使用令牌而非数组索引，以便 onCancel 跨 actor 精确移除特定等待者。
    private var waiters: [(token: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

    init(maxConcurrent: Int = 2) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// 在受限并发池中执行异步操作（排队等待执行槽）。
    /// - Parameter operation: 后台执行的 CPU/IO 密集段（闭包内可继续 await）。
    /// - Returns: 操作结果
    /// - Throws: CancellationError（等待期间被取消），或操作自身的错误。
    func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquireSlot()
        defer { releaseSlot() }
        // 获得槽位后再次检查取消——等待期间可能已被取消但槽位恰好释放
        try Task.checkCancellation()
        return try await operation()
    }

    // MARK: - 执行槽

    /// 获取执行槽。有可用槽位时直接返回；否则进入可取消的等待队列。
    private func acquireSlot() async throws {
        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }

        // 可取消等待：withTaskCancellationHandler 在任务取消时回调，
        // 通过 actor 方法移除等待者并 resume(throwing: CancellationError)。
        let token = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                waiters.append((token, continuation))
            }
        } onCancel: {
            // onCancel 运行在非 actor 上下文，需 Task 跳回 actor 执行移除。
            // 使用 weak self 避免取消回调持有执行器强引用。
            Task { [weak self] in
                await self?.cancelWaiter(token: token)
            }
        }
        // 若执行到这里，说明 releaseSlot 已 resume 本等待者——槽位已在 releaseSlot 中递增。
    }

    /// 取消指定等待者：从队列移除并抛 CancellationError。
    /// 若等待者已被 releaseSlot 移除（槽位恰好释放），则不操作（continuation 已 resume）。
    private func cancelWaiter(token: UUID) {
        guard let idx = waiters.firstIndex(where: { $0.token == token }) else { return }
        let continuation = waiters.remove(at: idx).continuation
        continuation.resume(throwing: CancellationError())
    }

    private func releaseSlot() {
        inFlight -= 1
        if let next = waiters.first {
            waiters.removeFirst()
            // 将槽位移交给等待者（inFlight 递增），等待者从 acquireSlot 返回后即拥有槽位。
            inFlight += 1
            next.continuation.resume()
        }
    }
}
