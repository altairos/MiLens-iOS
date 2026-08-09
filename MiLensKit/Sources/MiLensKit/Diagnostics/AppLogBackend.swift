import Foundation

// AppLogBackend —— Kit 统一日志后端（H1 诊断链路接入）。
//
// 跨平台策略：Apple 平台（iOS/macOS）输出到 os.Logger（统一日志，Console.app /
// 系统日志可查）；非 Apple 平台（Linux CI 纯逻辑测试）保持空实现——诊断
// 状态机测试不受日志后端影响。
//
// 调用方约束：所有消息在输出前必须经 AppErrorHandler.sanitizeForLog 脱敏；
// 含照片、令牌、完整 URI 或用户内容的消息不得直接调用本后端。
// 本后端用 privacy: .public（已脱敏消息），保证 release 构建不被打码。

#if canImport(os)
import os
#endif

/// Kit 统一日志后端（命名空间）。
public enum AppLogBackend {

    #if canImport(os)
    private static let logger = Logger(subsystem: "com.milens.kit", category: "Diagnostics")
    #endif

    public static func debug(_ message: String) {
        #if canImport(os)
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    public static func info(_ message: String) {
        #if canImport(os)
        logger.info("\(message, privacy: .public)")
        #endif
    }

    public static func warn(_ message: String) {
        #if canImport(os)
        logger.warning("\(message, privacy: .public)")
        #endif
    }

    public static func error(_ message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #endif
    }
}
