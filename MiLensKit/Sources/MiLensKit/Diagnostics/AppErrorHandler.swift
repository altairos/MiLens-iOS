import Foundation

// AppErrorHandler — 统一错误处理工具。
// 逐行翻译自源端 shared/.../utils/AppErrorHandler.ets。
//
// 提供：
// - sanitizeForLog：日志脱敏（9 条正则规则）
// - classifyError：异常分类（10 类，含默认文案/级别/可重试）
// - toUserMessage / resolveLevel：基于 errorCodeMap 的用户文案与日志级别
// - withCatch / withCatchSync：安全执行包装器
// - debug / info / warn / error：日志输出（os.Logger 后端）

// MARK: - 错误码常量

private let DB_BUSY_CODE = 5
private let DB_LOCKED_CODE = 6
private let NETWORK_ERROR_MIN = 100
private let NETWORK_ERROR_MAX = 599
private let PERMISSION_CODE_MIN = 121
private let PERMISSION_CODE_MAX = 139
private let USER_CANCEL_CODE = 14000011
private let POSIX_ENOSPC = 27
private let WIN_DISK_FULL = 1224

// MARK: - 异常分类

/// 异常分类枚举（10 类）。对应源端 `ErrorCategory`。
/// rawValue 与源端字符串值完全一致（如 "DatabaseError"）。
public enum AppErrorCategory: String, CaseIterable {
    case database = "DatabaseError"
    case network = "NetworkError"
    case permission = "PermissionError"
    case media = "MediaError"
    case cancel = "CancelError"
    case storage = "StorageError"
    case validation = "ValidationError"
    case ai = "AiError"
    case filesystem = "FileSystemError"
    case unknown = "UnknownError"
}

// MARK: - 分类错误信息

/// 分类错误信息。对应源端 `ClassifiedError`。
public struct ClassifiedError {
    public var category: AppErrorCategory
    public var code: String
    public var message: String
    public var isRetryable: Bool

    public init(category: AppErrorCategory, code: String, message: String, isRetryable: Bool) {
        self.category = category
        self.code = code
        self.message = message
        self.isRetryable = isRetryable
    }
}

// MARK: - 错误输入

/// 错误输入载体。对应源端 classifyError 接收的 `{ code, message }` 对象。
/// iOS 侧补充 `domain`（NSError domain，L4）：HarmonyOS 无 domain 概念，
/// 传 nil 时走原有 code/message 判定，完全向后兼容。
public struct ErrorInput {
    public var code: Any?
    public var message: Any?
    /// iOS NSError domain（如 NSCocoaErrorDomain / PHPhotosErrorDomain）。可选。
    public var domain: String?

    public init(code: Any? = nil, message: Any? = nil, domain: String? = nil) {
        self.code = code
        self.message = message
        self.domain = domain
    }
}

// MARK: - 分类条目

/// 日志级别。对应源端 `ErrorCategoryEntry.level`。
public enum ErrorLogLevel: String, Sendable {
    case info, warn, error
}

/// 每个 category 对应的默认日志级别、用户文案与可重试标记。对应源端 `ErrorCategoryEntry`。
public struct ErrorCategoryEntry: Sendable {
    public var level: ErrorLogLevel
    public var defaultMessage: String
    public var retryable: Bool

    public init(level: ErrorLogLevel, defaultMessage: String, retryable: Bool) {
        self.level = level
        self.defaultMessage = defaultMessage
        self.retryable = retryable
    }
}

/// 每个 category 对应的默认条目。对应源端 `ErrorCodeMap`。
/// key 为 AppErrorCategory.rawValue 字符串。
public let errorCodeMap: [String: ErrorCategoryEntry] = [
    "DatabaseError":   ErrorCategoryEntry(level: .error, defaultMessage: "数据库暂时不可用，请稍后重试", retryable: true),
    "NetworkError":    ErrorCategoryEntry(level: .warn,  defaultMessage: "网络连接异常", retryable: true),
    "PermissionError": ErrorCategoryEntry(level: .warn,  defaultMessage: "需要相关权限才能继续", retryable: false),
    "MediaError":      ErrorCategoryEntry(level: .warn,  defaultMessage: "访问系统媒体库失败", retryable: true),
    "CancelError":     ErrorCategoryEntry(level: .info,  defaultMessage: "操作已取消", retryable: false),
    "StorageError":    ErrorCategoryEntry(level: .error, defaultMessage: "存储空间不足", retryable: false),
    "ValidationError": ErrorCategoryEntry(level: .info,  defaultMessage: "输入不合法", retryable: false),
    "AiError":         ErrorCategoryEntry(level: .warn,  defaultMessage: "AI 模型暂不可用，已降级", retryable: false),
    "FileSystemError": ErrorCategoryEntry(level: .warn,  defaultMessage: "文件读写失败", retryable: false),
    "UnknownError":    ErrorCategoryEntry(level: .error, defaultMessage: "操作失败，请重试", retryable: true),
]

// MARK: - AppErrorHandler

/// 统一错误处理工具（命名空间）。对应源端 `AppErrorHandler` class。
public enum AppErrorHandler {

    // 日志后端：测试仅需验证不抛错，用 print 即可（跨平台兼容）

    // MARK: sanitizeForLog 预编译正则

    /// 9 条脱敏正则规则（pattern, template）。顺序与源端一致。
    private static let sanitizeRules: [(NSRegularExpression, String)] = {
        func regex(_ pattern: String) -> NSRegularExpression {
            // swiftlint:disable:next force_try
            try! NSRegularExpression(pattern: pattern)
        }
        return [
            // 1. credentials → [REDACTED]
            (regex("(?i)(authorization|token|password|secret|cookie)(\\s*[:=]\\s*)[^\\s,;]+"), "$1$2[REDACTED]"),
            // 2. content/file/datashare:// URIs → [URI]
            (regex("(?i)\\b(?:content|file|datashare)://[^\\s]+"), "[URI]"),
            // 3. /data/storage|app|user/ paths → [PATH]
            (regex("(?i)/data/(?:storage|app|user)/[^\\s]+"), "[PATH]"),
            // 4. /storage/ paths → [PATH]
            (regex("(?i)/storage/[^\\s]+"), "[PATH]"),
            // 5. IPv4 → [IP]
            (regex("\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b"), "[IP]"),
            // 6. long hex secrets (>=32 hex chars) → [SECRET]
            (regex("(?i)\\b[a-f0-9]{32,}\\b"), "[SECRET]"),
            // 7. User-Agent Mozilla/ → [UA]Mozilla/
            (regex("(?i)\\bMozilla/"), "[UA]Mozilla/"),
            // 8. long base64 (>=64 chars) → [B64]
            (regex("\\b[A-Za-z0-9+/]{64,}={0,2}\\b"), "[B64]"),
            // 9. Photos localIdentifier（UUID/L… 格式，L5）→ [PHID]
            (regex("(?i)\\b[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}/L[^,\\s)]*"), "[PHID]"),
        ]
    }()

    /// 移除日志中的敏感信息（凭据/URI/路径/IP/长 hex 密钥/UA/长 base64/照片标识）。对应源端 `sanitizeForLog`。
    public static func sanitizeForLog(_ value: String) -> String {
        var result = value
        for (regex, template) in sanitizeRules {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }

    /// 日志脱敏（L5）：系统照片库 localIdentifier 仅保留前缀，日志不落完整标识。
    /// 保留前缀用于关联同一照片的多条错误日志（诊断可跟踪性），短标识原样返回。
    public static func redactIdentifier(_ identifier: String) -> String {
        guard identifier.count > 10 else { return identifier }
        return String(identifier.prefix(10)) + "…"
    }

    // MARK: 日志方法
    // H1 诊断链路接入：输出到 AppLogBackend（Apple 平台 os.Logger，Linux 空实现）。
    // 消息与错误明细均先经 sanitizeForLog 脱敏再输出。

    public static func debug(_ tag: String, _ msg: String) {
        AppLogBackend.debug("[\\(tag)] \\(sanitizeForLog(msg))")
    }

    public static func info(_ tag: String, _ msg: String) {
        AppLogBackend.info("[\\(tag)] \\(sanitizeForLog(msg))")
    }

    public static func warn(_ tag: String, _ msg: String, _ err: ErrorInput? = nil) {
        AppLogBackend.warn("[\\(tag)] \\(sanitizeForLog(msg))\\(errSuffix(err))")
    }

    public static func error(_ tag: String, _ msg: String, _ err: ErrorInput? = nil) {
        AppLogBackend.error("[\\(tag)] \\(sanitizeForLog(msg))\\(errSuffix(err))")
    }

    /// 错误明细后缀（code/message 均脱敏）；err 为 nil 或全空时返回空串。
    private static func errSuffix(_ err: ErrorInput?) -> String {
        guard let err else { return "" }
        var parts: [String] = []
        // 直接读属性避免 if-let 绑定（Any? 绑定仅用于 String(describing:) 时
        // 被 Swift 6.1 工具链误报 unused；语义不变）
        if err.code != nil {
            parts.append("code=\(sanitizeForLog(String(describing: err.code)))")
        }
        if err.message != nil {
            parts.append("msg=\(sanitizeForLog(String(describing: err.message)))")
        }
        return parts.isEmpty ? "" : " (" + parts.joined(separator: " ") + ")"
    }

    // MARK: 安全执行包装器

    /// 安全执行异步函数，出错时记录日志并返回 fallback。对应源端 `withCatch`。
    public static func withCatch<T>(
        _ tag: String,
        fn: () async throws -> T,
        fallback: T,
        level: ErrorLogLevel = .warn
    ) async -> T {
        do {
            return try await fn()
        } catch {
            let nsError = error as NSError
            let input = ErrorInput(code: nsError.code, message: String(describing: error), domain: nsError.domain)
            if level == .error {
                AppErrorHandler.error(tag, "withCatch failed", input)
            } else {
                AppErrorHandler.warn(tag, "withCatch failed", input)
            }
            return fallback
        }
    }

    /// 安全执行同步函数，出错时记录日志并返回 fallback。对应源端 `withCatchSync`。
    public static func withCatchSync<T>(
        _ tag: String,
        fn: () throws -> T,
        fallback: T,
        level: ErrorLogLevel = .warn
    ) -> T {
        do {
            return try fn()
        } catch {
            let nsError = error as NSError
            let input = ErrorInput(code: nsError.code, message: String(describing: error), domain: nsError.domain)
            if level == .error {
                AppErrorHandler.error(tag, "withCatchSync failed", input)
            } else {
                AppErrorHandler.warn(tag, "withCatchSync failed", input)
            }
            return fallback
        }
    }

    // MARK: 异常分类

    /// 对异常进行分类（10 类优先级判定）。对应源端 `classifyError`。
    /// L4：优先使用 iOS NSError domain 判定（domain 比 code/message 更可靠），
    /// domain 为 nil 或未命中已知域时回落原有 code/message 规则。
    public static func classifyError(_ input: ErrorInput) -> ClassifiedError {
        let codeNum = parseCode(input.code)
        let msgStr = parseMessage(input.message)

        // 0. iOS NSError domain 优先判定（L4）
        if let domain = input.domain {
            switch domain {
            case "NSPOSIXErrorDomain":
                // Darwin errno：28=ENOSPC（磁盘满）、13=EACCES、2=ENOENT
                if codeNum == 28 {
                    return ClassifiedError(category: .storage, code: String(codeNum),
                                           message: msgStr, isRetryable: false)
                }
                if codeNum == 13 {
                    return ClassifiedError(category: .permission, code: String(codeNum),
                                           message: msgStr, isRetryable: false)
                }
                if codeNum == 2 {
                    return ClassifiedError(category: .filesystem, code: String(codeNum),
                                           message: msgStr, isRetryable: false)
                }
            case "NSCocoaErrorDomain":
                // 文件写空间不足 / 卷只读 → 存储
                if codeNum == 516 || codeNum == 640 || codeNum == 642 {
                    return ClassifiedError(category: .storage, code: String(codeNum),
                                           message: msgStr, isRetryable: false)
                }
                // 用户取消（AppKit/UIKit 取消动作统一码）
                if codeNum == 3072 {
                    return ClassifiedError(category: .cancel, code: String(codeNum),
                                           message: msgStr, isRetryable: false)
                }
                // 文件不存在（写 4 / 读 260）
                if codeNum == 4 || codeNum == 260 {
                    return ClassifiedError(category: .filesystem, code: String(codeNum),
                                           message: msgStr, isRetryable: false)
                }
                // 无读写权限（写 513 / 读 257）
                if codeNum == 513 || codeNum == 257 {
                    return ClassifiedError(category: .permission, code: String(codeNum),
                                           message: msgStr, isRetryable: false)
                }
                // Core Data 持久化错误区间
                if codeNum >= 134030 && codeNum <= 134099 {
                    return ClassifiedError(category: .database, code: String(codeNum),
                                           message: msgStr, isRetryable: true)
                }
            case "PHPhotosErrorDomain":
                // Photos framework：系统相册访问/资源变更
                return ClassifiedError(category: .media, code: String(codeNum),
                                       message: msgStr, isRetryable: true)
            case "NSURLErrorDomain":
                // 网络：超时/无法连接/连接丢失可重试，其余不可重试
                return ClassifiedError(category: .network, code: String(codeNum),
                                       message: msgStr,
                                       isRetryable: codeNum == -1001 || codeNum == -1004 || codeNum == -1005)
            case "SwiftDataErrorDomain":
                return ClassifiedError(category: .database, code: String(codeNum),
                                       message: msgStr, isRetryable: true)
            default:
                break
            }
        }

        // 1. 数据库错误 (SQLite error codes: 5~20, 26, 28)
        if (codeNum >= 5 && codeNum <= 20) || codeNum == 26 || codeNum == 28 {
            let isRetryable = codeNum == DB_BUSY_CODE || codeNum == DB_LOCKED_CODE
            return ClassifiedError(category: .database, code: String(codeNum),
                                   message: msgStr, isRetryable: isRetryable)
        }

        // 2. 权限错误 (HarmonyOS 权限错误码 121~139，或明确的 permission denied)
        if (codeNum >= PERMISSION_CODE_MIN && codeNum <= PERMISSION_CODE_MAX) ||
           msgStr.contains("permission denied") ||
           msgStr.contains("not granted") ||
           msgStr.contains("permission not granted") ||
           (msgStr.contains("permission") && msgStr.contains("denied")) {
            return ClassifiedError(category: .permission, code: String(codeNum),
                                   message: msgStr, isRetryable: false)
        }

        // 3. 媒体库错误
        if msgStr.contains("photoaccesshelper") || msgStr.contains("medialibrary") ||
           msgStr.contains("photoasset") || msgStr.contains("mediastore") ||
           msgStr.contains("photo view picker") || msgStr.contains("fetch result") ||
           msgStr.contains("photo select") {
            return ClassifiedError(category: .media, code: String(codeNum),
                                   message: msgStr, isRetryable: true)
        }

        // 4. 取消错误
        if codeNum == USER_CANCEL_CODE ||
           msgStr.contains("cancel") || msgStr.contains("aborted") ||
           msgStr.contains("user cancel") {
            return ClassifiedError(category: .cancel, code: String(codeNum),
                                   message: msgStr, isRetryable: false)
        }

        // 5. 存储空间不足
        if codeNum == POSIX_ENOSPC || codeNum == WIN_DISK_FULL ||
           msgStr.contains("enospace") || msgStr.contains("enospc") ||
           msgStr.contains("quota") || msgStr.contains("disk full") ||
           msgStr.contains("not enough space") || msgStr.contains("no space left") ||
           msgStr.contains("storage full") {
            return ClassifiedError(category: .storage, code: String(codeNum),
                                   message: msgStr, isRetryable: false)
        }

        // 6. 文件系统错误
        if codeNum == 3 || codeNum == 13 || codeNum == 17 || codeNum == 39 ||
           msgStr.contains("permission") || msgStr.contains("access") ||
           msgStr.contains("file") || msgStr.contains("enoent") || msgStr.contains("eacces") ||
           msgStr.contains("mkdir") || msgStr.contains("copyfile") {
            return ClassifiedError(category: .filesystem, code: String(codeNum),
                                   message: msgStr, isRetryable: false)
        }

        // 7. 网络错误 (HTTP status codes 100~599)
        if (codeNum >= NETWORK_ERROR_MIN && codeNum <= NETWORK_ERROR_MAX) ||
           msgStr.contains("network") || msgStr.contains("timeout") ||
           msgStr.contains("http") || msgStr.contains("fetch") ||
           msgStr.contains("socket") || msgStr.contains("dns") ||
           msgStr.contains("connection") {
            return ClassifiedError(category: .network, code: String(codeNum),
                                   message: msgStr,
                                   isRetryable: codeNum >= 500 || codeNum == 0 || codeNum == -1)
        }

        // 8. AI 错误
        if msgStr.contains("ai") || msgStr.contains("model") || msgStr.contains("tensor") ||
           msgStr.contains("inference") || msgStr.contains("clip") || msgStr.contains("mindspore") ||
           msgStr.contains("embedding") || msgStr.contains("neural") || msgStr.contains("onnx") {
            return ClassifiedError(category: .ai, code: String(codeNum),
                                   message: msgStr, isRetryable: false)
        }

        // 9. 验证错误
        if msgStr.contains("validate") || msgStr.contains("invalid") || msgStr.contains("required") ||
           msgStr.contains("format") || msgStr.contains("constraint") ||
           msgStr.contains("not null") || msgStr.contains("unique") {
            return ClassifiedError(category: .validation, code: String(codeNum),
                                   message: msgStr, isRetryable: false)
        }

        // 10. 未知错误
        return ClassifiedError(category: .unknown, code: String(codeNum),
                               message: msgStr, isRetryable: false)
    }

    /// 根据分类返回面向用户的默认文案。对应源端 `toUserMessage`。
    public static func toUserMessage(_ input: ErrorInput) -> String {
        let classified = classifyError(input)
        return errorCodeMap[classified.category.rawValue]?.defaultMessage
            ?? errorCodeMap[AppErrorCategory.unknown.rawValue]!.defaultMessage
    }

    /// 根据分类返回默认日志级别。对应源端 `resolveLevel`。
    public static func resolveLevel(_ input: ErrorInput) -> ErrorLogLevel {
        let classified = classifyError(input)
        return errorCodeMap[classified.category.rawValue]?.level ?? .error
    }

    // MARK: - 私有辅助

    /// 解析 code 为 Int（兼容 number/string）。
    private static func parseCode(_ code: Any?) -> Int {
        if let n = code as? Int { return n }
        if let n = code as? Double { return Int(n) }
        if let s = code as? String { return Int(s) ?? -1 }
        return -1
    }

    /// 解析 message 为小写字符串。
    private static func parseMessage(_ message: Any?) -> String {
        if let s = message as? String { return s.lowercased() }
        if message != nil { return String(describing: message!).lowercased() }
        return ""
    }
}
