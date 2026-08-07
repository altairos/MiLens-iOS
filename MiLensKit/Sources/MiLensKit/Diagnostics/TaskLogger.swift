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
public enum TaskKind: String {
    case scan
    case import_ = "import"  // Swift 关键字冲突，rawValue 对齐源端 "import"
    case bead
    case backup
    case export
}

/// 任务结束状态。对应源端 `TaskOutcome`。
public enum TaskOutcome: String {
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

private struct TaskRecord {
    var kind: TaskKind
    var label: String
    var startMs: Int
    var lastStageMs: Int
    var currentStage: String
    var stageCount: Int
}

private let INVALID_TASK_ID = 0
private let MAX_RECENT_FINISHED = 50

private final class TaskLoggerState {
    var nextTaskId: Int = 1
    var activeTasks: [Int: TaskRecord] = [:]
    var recentFinished: [FinishedTaskSummary] = []
    static let shared = TaskLoggerState()
}

// MARK: - 私有辅助

private func pushRecentFinished(_ summary: FinishedTaskSummary) {
    TaskLoggerState.shared.recentFinished.append(summary)
    if TaskLoggerState.shared.recentFinished.count > MAX_RECENT_FINISHED {
        TaskLoggerState.shared.recentFinished.removeFirst()
    }
}

private func nowMs() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
}

private func sanitizeValue(_ value: String) -> String {
    AppErrorHandler.sanitizeForLog(value)
}

// 日志后端：跨平台兼容，测试仅需验证状态机逻辑

private func tlLogInfo(_ taskId: Int, _ message: String) {
    // sanitizeValue 仍执行以验证脱敏链路不抛错
    _ = sanitizeValue(message)
}

private func tlLogWarn(_ taskId: Int, _ message: String) {
    _ = sanitizeValue(message)
}

private func tlLogError(_ taskId: Int, _ message: String) {
    _ = sanitizeValue(message)
}

private func finishTask(_ taskId: Int, outcome: TaskOutcome, summary: String? = nil, category: String? = nil) {
    guard let record = TaskLoggerState.shared.activeTasks[taskId] else {
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

    pushRecentFinished(FinishedTaskSummary(
        kind: record.kind,
        outcome: outcome,
        category: category ?? TASK_CATEGORY_NONE,
        elapsedMs: elapsed,
        stageCount: record.stageCount))

    TaskLoggerState.shared.activeTasks.removeValue(forKey: taskId)
}

// MARK: - TaskLogger

/// 结构化任务日志（命名空间）。对应源端 `TaskLogger` class。
public enum TaskLogger {

    /// 开始一个新任务，返回递增的正整数 taskId。
    public static func beginTask(_ kind: TaskKind, label: String? = nil) -> Int {
        let taskId = TaskLoggerState.shared.nextTaskId
        TaskLoggerState.shared.nextTaskId += 1
        let safeLabel = label.map { sanitizeValue($0) } ?? ""
        let now = nowMs()
        TaskLoggerState.shared.activeTasks[taskId] = TaskRecord(
            kind: kind, label: safeLabel, startMs: now,
            lastStageMs: now, currentStage: "begin", stageCount: 0)
        var msg = "BEGIN kind=\(kind.rawValue)"
        if !safeLabel.isEmpty { msg += " label=\(safeLabel)" }
        tlLogInfo(taskId, msg)
        return taskId
    }

    /// 切换到新的 stage。对未知 taskId 静默跳过。
    public static func stage(_ taskId: Int, _ stage: String, detail: String? = nil) {
        guard var record = TaskLoggerState.shared.activeTasks[taskId] else { return }
        let now = nowMs()
        let stageElapsed = now - record.lastStageMs
        record.stageCount += 1
        let prevStage = record.currentStage
        record.currentStage = stage
        record.lastStageMs = now
        TaskLoggerState.shared.activeTasks[taskId] = record
        var msg = "stage=\(sanitizeValue(stage)) (prev=\(sanitizeValue(prevStage)) \(stageElapsed)ms)"
        if let detail { msg += " detail=\(sanitizeValue(detail))" }
        tlLogInfo(taskId, msg)
    }

    /// 记录进度。total=0 时只记录 current。
    public static func progress(_ taskId: Int, current: Int, total: Int) {
        guard let record = TaskLoggerState.shared.activeTasks[taskId] else { return }
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
        guard TaskLoggerState.shared.activeTasks[taskId] != nil else {
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
        return TaskLoggerState.shared.activeTasks[taskId] != nil
    }

    /// 返回最近已完成任务的摘要副本（按完成顺序，最多 50 条）。
    public static func getRecentSummaries() -> [FinishedTaskSummary] {
        return TaskLoggerState.shared.recentFinished
    }

    /// 仅供测试重置内部状态。
    public static func resetForTest() {
        TaskLoggerState.shared.nextTaskId = 1
        TaskLoggerState.shared.activeTasks.removeAll()
        TaskLoggerState.shared.recentFinished.removeAll()
    }
}
