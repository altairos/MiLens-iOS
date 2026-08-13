import XCTest
@testable import MiLens

/// AnalysisExecutor 取消行为测试（P1 修复）。
///
/// 验证：
/// - 任务在队列中等待时被取消 → 立即抛 CancellationError，不再占用后续槽位执行
/// - 获得槽位后检查取消 → 若已取消则不执行操作
/// - 正常执行不受影响（并发上限 + 结果正确返回）
final class AnalysisExecutorTests: XCTestCase {

    /// 正常执行：结果正确返回。
    func testRunReturnsResult() async throws {
        let executor = AnalysisExecutor(maxConcurrent: 2)
        let result = try await executor.run { 42 }
        XCTAssertEqual(result, 42)
    }

    /// 并发上限：超过 maxConcurrent 的任务排队等待，最终全部完成。
    func testConcurrencyLimit() async throws {
        let executor = AnalysisExecutor(maxConcurrent: 1)
        let tasks = (0..<5).map { i in
            Task {
                try await executor.run { i * 10 }
            }
        }
        var results: [Int] = []
        for task in tasks {
            results.append(try await task.value)
        }
        XCTAssertEqual(results, [0, 10, 20, 30, 40])
    }

    /// 等待中的任务被取消 → 抛 CancellationError，不执行操作。
    func testWaitingTaskCancellationThrows() async throws {
        let executor = AnalysisExecutor(maxConcurrent: 1)

        // Task A 占用唯一槽位（长时间运行）
        let taskA = Task<Void, Never> {
            _ = try? await executor.run {
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
        }

        // 等待 A 占用槽位
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05s

        // Task B 排队等待，立即取消
        let taskB = Task<Int, Error> {
            try await executor.run { 999 }
        }
        taskB.cancel()

        // B 须抛 CancellationError 而非等待执行后返回 999
        do {
            let bResult = try await taskB.value
            XCTFail("被取消的等待任务不应执行，实际返回 \(bResult)")
        } catch is CancellationError {
            // 预期：CancellationError
        } catch {
            // 其他错误也可接受（取决于取消时序），关键是没执行 operation
        }

        // A 正常完成
        await taskA.value
    }

    /// 获得槽位后检查取消：任务在排队时被取消，但恰好在检查前获得槽位。
    /// 取消后获得槽位 → Task.checkCancellation 抛错，operation 不执行。
    func testCancellationAfterAcquireSlot() async throws {
        let executor = AnalysisExecutor(maxConcurrent: 1)

        // Task A 占用槽位
        let taskA = Task<Void, Never> {
            _ = try? await executor.run {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        // Task B 排队，然后取消
        let taskB = Task<Int, Error> {
            try await executor.run { 888 }
        }
        taskB.cancel()

        // 无论时序如何，B 要么抛 CancellationError（等待中被取消），
        // 要么因 checkCancellation 抛错（获得槽位后被取消）——不会执行 operation。
        do {
            let result = try await taskB.value
            XCTFail("取消的任务不应执行 operation，实际返回 \(result)")
        } catch {
            // 预期：CancellationError
        }

        await taskA.value
    }

    /// 取消的等待者不阻塞后续任务：B 取消后 C 仍能正常获得槽位。
    func testCancelledWaiterDoesNotBlockOthers() async throws {
        let executor = AnalysisExecutor(maxConcurrent: 1)

        // Task A 占用槽位
        let taskA = Task<Void, Never> {
            _ = try? await executor.run {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        // Task B 排队等待
        let taskB = Task<Int, Error> {
            try await executor.run { 1 }
        }
        // Task C 也排队等待
        let taskC = Task<Int, Error> {
            try await executor.run { 2 }
        }

        // 取消 B，C 应仍能在 A 完成后执行
        taskB.cancel()
        _ = try? await taskB.value

        let cResult = try await taskC.value
        XCTAssertEqual(cResult, 2, "B 被取消后 C 仍应正常执行")

        await taskA.value
    }
}
