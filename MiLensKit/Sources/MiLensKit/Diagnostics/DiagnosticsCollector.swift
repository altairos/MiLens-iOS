import Foundation

// DiagnosticsCollector — 诊断信息收集器。
// 逐行翻译自源端 shared/.../utils/DiagnosticsCollector.ets。
//
// 职责：
// - 把分散的诊断信号汇总为一份 Markdown 纯文本
// - 所有动态字段经 AppErrorHandler.sanitizeForLog 脱敏
// - 统计近期任务的失败分类，按 count 降序排序
// 纯函数，无系统 API 依赖。

// MARK: - 输入/输出类型

/// 诊断报告输入。对应源端 `DiagnosticsInput`。
/// 所有字符串字段会被再次脱敏，调用方无需预脱敏。
public struct DiagnosticsInput {
    public var appVersionName: String
    public var appVersionCode: Int
    public var bundleName: String
    public var sdkApiVersion: Int
    public var distributionApiVersion: Int
    public var deviceType: String
    public var dbVersion: Int
    public var taskSummaries: [FinishedTaskSummary]
    public var aiDiagnostics: String
    public var visionDiagnostics: String
    public var cacheSizeText: String
    public var generatedAtMs: Double

    public init(appVersionName: String, appVersionCode: Int, bundleName: String,
                sdkApiVersion: Int, distributionApiVersion: Int, deviceType: String,
                dbVersion: Int, taskSummaries: [FinishedTaskSummary],
                aiDiagnostics: String, visionDiagnostics: String,
                cacheSizeText: String, generatedAtMs: Double) {
        self.appVersionName = appVersionName
        self.appVersionCode = appVersionCode
        self.bundleName = bundleName
        self.sdkApiVersion = sdkApiVersion
        self.distributionApiVersion = distributionApiVersion
        self.deviceType = deviceType
        self.dbVersion = dbVersion
        self.taskSummaries = taskSummaries
        self.aiDiagnostics = aiDiagnostics
        self.visionDiagnostics = visionDiagnostics
        self.cacheSizeText = cacheSizeText
        self.generatedAtMs = generatedAtMs
    }
}

/// 失败任务分类计数。对应源端 `CategoryCount`。
public struct CategoryCount: Equatable {
    public var category: String
    public var count: Int

    public init(category: String, count: Int) {
        self.category = category
        self.count = count
    }
}

/// 任务统计摘要。对应源端 `TaskStats`。
public struct TaskStats: Equatable {
    public var total: Int
    public var success: Int
    public var failed: Int
    public var canceled: Int
    public var failedByCategory: [CategoryCount]

    public init(total: Int, success: Int, failed: Int, canceled: Int,
                failedByCategory: [CategoryCount]) {
        self.total = total
        self.success = success
        self.failed = failed
        self.canceled = canceled
        self.failedByCategory = failedByCategory
    }
}

// MARK: - 私有常量

private let PRIVACY_FOOTER =
    "隐私说明：本报告不包含照片、令牌、完整 URI 或数据库内容；所有路径/URI/IP 已脱敏。"

// MARK: - 公共 API

/// 把毫秒时间戳格式化为 'yyyy-MM-dd HH:mm:ss'。对应源端 `formatTimestamp`。
/// 使用本地时区。NaN/负数/Infinity 返回 "unknown"。
public func formatTimestamp(_ ms: Double) -> String {
    if ms.isNaN || ms.isInfinite || ms < 0 {
        return "unknown"
    }
    let date = Date(timeIntervalSince1970: ms / 1000.0)
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    guard let y = comps.year, let mo = comps.month, let d = comps.day,
          let h = comps.hour, let mi = comps.minute, let s = comps.second else {
        return "unknown"
    }
    return "\(y)-\(pad2(mo))-\(pad2(d)) \(pad2(h)):\(pad2(mi)):\(pad2(s))"
}

private func pad2(_ n: Int) -> String {
    n < 10 ? "0\(n)" : String(n)
}

/// 诊断级脱敏（最后一道防线）。对应源端 `safe`。
private func safe(_ value: String) -> String {
    AppErrorHandler.sanitizeForLog(value)
}

/// 统计任务摘要中的失败分类。对应源端 `summarizeTaskCategories`。
/// 只统计 outcome=.failed 的任务，按 category 聚合计数并按 count 降序排序。
public func summarizeTaskCategories(_ summaries: [FinishedTaskSummary]) -> TaskStats {
    var success = 0
    var failed = 0
    var canceled = 0
    var categoryMap: [String: Int] = [:]
    for s in summaries {
        switch s.outcome {
        case .success:
            success += 1
        case .failed:
            failed += 1
            let key = s.category.isEmpty ? TASK_CATEGORY_NONE : s.category
            categoryMap[key, default: 0] += 1
        case .canceled:
            canceled += 1
        }
    }
    var failedByCategory = categoryMap.map { CategoryCount(category: $0.key, count: $0.value) }
    failedByCategory.sort { $0.count > $1.count }
    return TaskStats(total: summaries.count, success: success, failed: failed,
                     canceled: canceled, failedByCategory: failedByCategory)
}

/// 构建 Markdown 格式的诊断报告。对应源端 `buildDiagnosticsReport`。
public func buildDiagnosticsReport(_ input: DiagnosticsInput) -> String {
    var lines: [String] = []
    lines.append("# 「咪Lens」诊断信息")
    lines.append("")
    lines.append("生成时间：\(formatTimestamp(input.generatedAtMs))")
    lines.append("")

    lines.append("## 应用")
    lines.append("- 版本：\(safe(input.appVersionName)) (\(input.appVersionCode))")
    lines.append("- 包名：\(safe(input.bundleName))")
    lines.append("")

    lines.append("## 设备")
    lines.append("- API Level：\(input.sdkApiVersion)")
    lines.append("- 发行版版本：\(input.distributionApiVersion)")
    lines.append("- 设备类型：\(safe(input.deviceType))")
    lines.append("")

    lines.append("## 数据库")
    lines.append("- 版本：\(input.dbVersion)")
    lines.append("")

    let stats = summarizeTaskCategories(input.taskSummaries)
    lines.append("## 近期任务统计")
    lines.append("- 总数：\(stats.total)")
    lines.append("- 成功：\(stats.success)")
    lines.append("- 失败：\(stats.failed)")
    lines.append("- 取消：\(stats.canceled)")
    if !stats.failedByCategory.isEmpty {
        lines.append("")
        lines.append("### 失败任务分类")
        for cc in stats.failedByCategory {
            lines.append("- \(safe(cc.category))：\(cc.count)")
        }
    }
    lines.append("")

    lines.append("## AI 模型状态")
    let aiSafe = safe(input.aiDiagnostics)
    lines.append("- " + (aiSafe.isEmpty ? "（未运行）" : aiSafe))
    lines.append("")

    lines.append("## 视觉预过滤")
    let visionSafe = safe(input.visionDiagnostics)
    lines.append("- " + (visionSafe.isEmpty ? "（未运行）" : visionSafe))
    lines.append("")

    lines.append("## 缓存")
    let cacheSafe = safe(input.cacheSizeText)
    lines.append("- 大小：" + (cacheSafe.isEmpty ? "未知" : cacheSafe))
    lines.append("")

    lines.append("---")
    lines.append(PRIVACY_FOOTER)
    lines.append("")

    return lines.joined(separator: "\n")
}

/// 默认文件名（不含扩展名）。对应源端 `defaultReportBaseName`。
/// 例如：milens-diagnostics-20260720-153000
public func defaultReportBaseName(_ input: DiagnosticsInput) -> String {
    let date = Date(timeIntervalSince1970: input.generatedAtMs / 1000.0)
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    guard let y = comps.year, let mo = comps.month, let d = comps.day,
          let h = comps.hour, let mi = comps.minute, let s = comps.second else {
        return "milens-diagnostics-unknown"
    }
    return "milens-diagnostics-\(y)\(pad2(mo))\(pad2(d))-\(pad2(h))\(pad2(mi))\(pad2(s))"
}
