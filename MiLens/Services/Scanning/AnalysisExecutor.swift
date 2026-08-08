//  AnalysisExecutor —— 受限并发的图像分析后台执行器（P1 性能）。
//
//  所有 CPU 密集段（JPEG 解码、Laplacian、pHash、VNRequest、CLIP 预处理）
//  经本执行器运行，保证像素计算不阻塞 MainActor，同时限制并发防止 CPU 过载
//  （5000 张图库扫描/评分场景）。
//
//  用法：QualityScorer / ScanService 把「读文件 + 解码 + 计算」整体放入
//  `executor.run`，只把 SwiftData 读写与进度状态留在 MainActor。

import Foundation

actor AnalysisExecutor {

    /// 最大并发数（internal 只读——调用方按此分批提交任务）。
    let maxConcurrent: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int = 2) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// 在受限并发池中执行异步操作（排队等待执行槽）。
    /// - Parameter operation: 后台执行的 CPU/IO 密集段（闭包内可继续 await）。
    /// - Returns: 操作结果
    func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await acquireSlot()
        defer { releaseSlot() }
        return try await operation()
    }

    // MARK: - 执行槽

    private func acquireSlot() async {
        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func releaseSlot() {
        inFlight -= 1
        if !waiters.isEmpty {
            inFlight += 1
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}
