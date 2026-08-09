import Foundation

// TaskLogger — 结构化任务日志。
// 逐行翻译自源端 shared/.../utils/TaskLogger.ets。
//
// 为长任务（扫描/导入/拼豆/备份/导出）提供统一的结构化日志：
// - 全局递增 taskId，便于按任务过滤
// - 每个任务记录 kind/stage/进度/耗时/结果
// - 失败时自动经 AppErrorHandler.classifyError 分类
// - 所有 label/detail 经 sanitizeForLog 脱敏
// - 未知 taskId 静默跳过；complete 后幂等；recentFinished FIFO 上限 50

// MARK: - 类型

/// 任务种类。对应源端 `TaskKind`。
public enum TaskKind: String, Sendable {
    case scan
    case import_ = "import"  // Swift 关键字冲突，rawValue 对齐源端 "import"
    case bead
    case backup
    case export
}

/// 任务结束状态。对应源端 `TaskOutcome`。
public enum TaskOutcome: String, Sendable {
    case success, canceled, failed
}

/// 成功/取消任务的 category 占位值。对应源端 `TASK_CATEGORY_NONE`。
public let TASK_CATEGORY_NONE = "None"

/// 已完成任务摘要（不含 label/detail 原文，保护隐私）。对应源端 `FinishedTaskSummary`。
public struct FinishedTaskSummary: Equatable {
    public var kind: TaskKind
    public var outcome: TaskOutcome
    /// ErrorCategory rawValue 字符串；成功/取消为 "None"
    public var category: String
    /// 总耗时毫秒
    public var elapsedMs: Int
    /// 阶段切换次数
    public var stageCount: Int

    public init(kind: TaskKind, outcome: TaskOutcome, category: String,
                elapsedMs: Int, stageCount: Int) {
        self.kind = kind
        self.outcome = outcome
        self.category = category
        self.elapsedMs = elapsedMs
        self.stageCount = stageCount
    }
}

// MARK: - 内部状态

private struct TaskRecord: Sendable {
    var kind: TaskKind
    var label: String
    var startMs: Int
    var lastStageMs: Int
    var currentStage: String
    var stageCount: Int
}

private let INVALID_TASK_ID = 0
private let MAX_RECENT_FINISHED = 50

private final class TaskLoggerState: @unchecked Sendable {
    // 线程安全：TaskLogger 从任意队列调用（扫描/导入/拼豆/备份/导出），
    // 所有状态访问经 lock 串行化；@unchecked Sendable 为锁保护的显式声明。
    private let lock = NSLock()
    private var nextTaskId: Int = 1
    private var activeTasks: [Int: TaskRecord] = [:]
    private var recentFinished: [FinishedTaskSummary] = []
    static let shared = TaskLoggerState()

    /// 分配 taskId 并登记新任务记录。
    func begin(_ record: TaskRecord) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let taskId = nextTaskId
        nextTaskId += 1
        activeTasks[taskId] = record
        return taskId
    }

    /// 读取任务记录副本；不存在返回 nil。
    func active(_ taskId: Int) -> TaskRecord? {
        lock.lock()
        defer { lock.unlock() }
        return activeTasks[taskId]
    }

    /// 任务记录原地更新（锁内完成读-改-写）；不存在返回 false。
    @discardableResult
    func updateActive(_ taskId: Int, _ mutate: (inout TaskRecord) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var record = activeTasks[taskId] else { return false }
        mutate(&record)
        activeTasks[taskId] = record
        return true
    }

    /// 原子读删任务记录（complete/fail/cancel 用）。
    func removeActive(_ taskId: Int) -> TaskRecord? {
        lock.lock()
        defer { lock.unlock() }
        return activeTasks.removeValue(forKey: taskId)
    }

    /// 追加完成摘要，FIFO 上限 MAX_RECENT_FINISHED。
    func appendFinished(_ summary: FinishedTaskSummary) {
        lock.lock()
        defer { lock.unlock() }
        recentFinished.append(summary)
        if recentFinished.count > MAX_RECENT_FINISHED {
            recentFinished.removeFirst()
        }
    }

    /// 已完成摘要副本（按完成顺序）。
    func allFinished() -> [FinishedTaskSummary] {
        lock.lock()
        defer { lock.unlock() }
        return recentFinished
    }

    /// 仅供测试重置内部状态。
    func resetAll() {
        lock.lock()
        defer { lock.unlock() }
        nextTaskId = 1
        activeTasks.removeAll()
        recentFinished.removeAll()
    }
}

private func nowMs() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
}

private func sanitizeValue(_ value: String) -> String {
    AppErrorHandler.sanitizeForLog(value)
}

// 日志后端：统一经 AppLogBackend 输出（Apple 平台 os.Logger；Linux 空实现）。
// 消息先经 sanitizeValue 脱敏，再交给后端。

private func tlLogInfo(_ taskId: Int, _ message: String) {
    AppLogBackend.info("TaskLogger[\(taskId)] \(sanitizeValue(message))")
}

private func tlLogWarn(_ taskId: Int, _ message: String) {
    AppLogBackend.warn("TaskLogger[\(taskId)] \(sanitizeValue(message))")
}

private func tlLogError(_ taskId: Int, _ message: String) {
    AppLogBackend.error("TaskLogger[\(taskId)] \(sanitizeValue(message))")
}

private func finishTask(_ taskId: Int, outcome: TaskOutcome, summary: String? = nil, category: String? = nil) {
    guard let record = TaskLoggerState.shared.removeActive(taskId) else {
        tlLogWarn(taskId, "complete ignored (unknown or already finished) outcome=\(outcome.rawValue)")
        return
    }
    let elapsed = nowMs() - record.startMs
    var line = "DONE kind=\(record.kind.rawValue) outcome=\(outcome.rawValue) elapsed=\(elapsed)ms stages=\(record.stageCount)"
    if let summary { line += " summary=\(sanitizeValue(summary))" }

    if outcome == .failed {
        tlLogError(taskId, line)
    } else {
        tlLogInfo(taskId, line)
    }

    TaskLoggerState.shared.appendFinished(FinishedTaskSummary(
        kind: record.kind,
        outcome: outcome,
        category: category ?? TASK_CATEGORY_NONE,
        elapsedMs: elapsed,
        stageCount: record.stageCount))
}

// MARK: - TaskLogger

/// 结构化任务日志（命名空间）。对应源端 `TaskLogger` class。
public enum TaskLogger {

    /// 开始一个新任务，返回递增的正整数 taskId。
    public static func beginTask(_ kind: TaskKind, label: String? = nil) -> Int {
        let safeLabel = label.map { sanitizeValue($0) } ?? ""
        let now = nowMs()
        let taskId = TaskLoggerState.shared.begin(TaskRecord(
            kind: kind, label: safeLabel, startMs: now,
            lastStageMs: now, currentStage: "begin", stageCount: 0))
        var msg = "BEGIN kind=\(kind.rawValue)"
        if !safeLabel.isEmpty { msg += " label=\(safeLabel)" }
        tlLogInfo(taskId, msg)
        return taskId
    }

    /// 切换到新的 stage。对未知 taskId 静默跳过。
    public static func stage(_ taskId: Int, _ stage: String, detail: String? = nil) {
        var stageElapsed = 0
        var prevStage = ""
        let updated = TaskLoggerState.shared.updateActive(taskId) { record in
            let now = nowMs()
            stageElapsed = now - record.lastStageMs
            prevStage = record.currentStage
            record.stageCount += 1
            record.currentStage = stage
            record.lastStageMs = now
        }
        guard updated else { return }
        var msg = "stage=\(sanitizeValue(stage)) (prev=\(sanitizeValue(prevStage)) \(stageElapsed)ms)"
        if let detail { msg += " detail=\(sanitizeValue(detail))" }
        tlLogInfo(taskId, msg)
    }

    /// 记录进度。total=0 时只记录 current。
    public static func progress(_ taskId: Int, current: Int, total: Int) {
        guard let record = TaskLoggerState.shared.active(taskId) else { return }
        if total > 0 {
            tlLogInfo(taskId, "stage=\(sanitizeValue(record.currentStage)) progress=\(current)/\(total)")
        } else {
            tlLogInfo(taskId, "stage=\(sanitizeValue(record.currentStage)) progress=\(current)")
        }
    }

    /// 任务成功完成。
    public static func complete(_ taskId: Int, summary: String? = nil) {
        finishTask(taskId, outcome: .success, summary: summary)
    }

    /// 任务失败：自动 classifyError 并把 category 写入 summary。
    public static func fail(_ taskId: Int, err: ErrorInput, summary: String? = nil) {
        guard TaskLoggerState.shared.active(taskId) != nil else {
            tlLogWarn(taskId, "fail ignored (unknown or already finished)")
            return
        }
        // classifyError 是纯函数不会 throw，直接调用（源端 try-catch 是 JS 防御性写法）
        let category = AppErrorHandler.classifyError(err).category
        let errSummary = "category=\(category.rawValue)"
        let fullSummary = summary != nil ? "\(errSummary) \(sanitizeValue(summary!))" : errSummary
        finishTask(taskId, outcome: .failed, summary: fullSummary, category: category.rawValue)
    }

    /// 任务被取消。
    public static func cancel(_ taskId: Int, summary: String? = nil) {
        finishTask(taskId, outcome: .canceled, summary: summary)
    }

    /// 任务是否仍在进行。
    public static func isActive(_ taskId: Int) -> Bool {
        if taskId == INVALID_TASK_ID { return false }
        return TaskLoggerState.shared.active(taskId) != nil
    }

    /// 返回最近已完成任务的摘要副本（按完成顺序，最多 50 条）。
    public static func getRecentSummaries() -> [FinishedTaskSummary] {
        return TaskLoggerState.shared.allFinished()
    }

    /// 仅供测试重置内部状态。
    public static func resetForTest() {
        TaskLoggerState.shared.resetAll()
    }
}
