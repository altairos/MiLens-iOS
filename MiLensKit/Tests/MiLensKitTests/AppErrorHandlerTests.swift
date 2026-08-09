import XCTest
@testable import MiLensKit

/// AppErrorHandler 测试。翻译自源端 shared/.../test/AppErrorHandler.test.ets（33 用例）。
/// 重点验证 sanitizeForLog 脱敏、classifyError 分类与 retryable、errorCodeMap 完整性、
/// toUserMessage/resolveLevel 映射、withCatch happy/fallback/level。
final class AppErrorHandlerTests: XCTestCase {

    // MARK: - sanitizeForLog

    func testSanitizeForLogRedactsCredentialsURIsPathsIPsAndLongHexSecrets() {
        let dirty = "token=abc123 /data/storage/el2/123/ ohone 10.0.0.1 secret 0123456789abcdef0123456789abcdef"
        let clean = AppErrorHandler.sanitizeForLog(dirty)
        XCTAssertFalse(clean.contains("abc123"))
        XCTAssertFalse(clean.contains("/data/storage/"))
        XCTAssertFalse(clean.contains("10.0.0.1"))
        XCTAssertFalse(clean.contains("0123456789abcdef0123456789abcdef"))
        XCTAssertTrue(clean.contains("[REDACTED]"))
        XCTAssertTrue(clean.contains("[PATH]"))
        XCTAssertTrue(clean.contains("[IP]"))
        XCTAssertTrue(clean.contains("[SECRET]"))
    }

    func testSanitizeForLogLeavesOrdinaryMessagesUntouched() {
        XCTAssertEqual(AppErrorHandler.sanitizeForLog("photos version updated: 42"),
                       "photos version updated: 42")
    }

    // MARK: - 日志 localIdentifier 脱敏（L5）

    func testSanitizeForLogRedactsPhotosLocalIdentifier() {
        let id = "3A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D/L0/001"
        let clean = AppErrorHandler.sanitizeForLog("load failed: \(id)")
        XCTAssertFalse(clean.contains(id))
        XCTAssertTrue(clean.contains("[PHID]"))
    }

    func testRedactIdentifierKeepsPrefixForDiagnosticCorrelation() {
        let id = "3A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D/L0/001"
        let redacted = AppErrorHandler.redactIdentifier(id)
        XCTAssertTrue(redacted.hasPrefix("3A1B2C3D-"))
        XCTAssertFalse(redacted.contains(id))
        XCTAssertTrue(redacted.hasSuffix("…"))
    }

    func testRedactIdentifierLeavesShortStringsUntouched() {
        XCTAssertEqual(AppErrorHandler.redactIdentifier("short"), "short")
        XCTAssertEqual(AppErrorHandler.redactIdentifier(""), "")
    }

    func testDebugInfoLogWithoutThrowing() {
        AppErrorHandler.debug("TestTag", "debug message")
        AppErrorHandler.info("TestTag", "info message")
    }

    func testWarnErrorAcceptOptionalErrorDetailWithoutThrowing() {
        AppErrorHandler.warn("TestTag", "warn message")
        AppErrorHandler.warn("TestTag", "warn with detail", ErrorInput(message: "boom"))
        let failDetail = ErrorInput(code: 500, message: "fail")
        AppErrorHandler.error("TestTag", "error message")
        AppErrorHandler.error("TestTag", "error with detail", failDetail)
    }

    // MARK: - withCatch

    func testWithCatchReturnsResolvedValueOnHappyPath() async {
        let result = await AppErrorHandler.withCatch("Tag", fn: { 42 }, fallback: -1)
        XCTAssertEqual(result, 42)
    }

    func testWithCatchReturnsFallbackOnFailure() async {
        let result = await AppErrorHandler.withCatch("Tag",
            fn: { throw NSError(domain: "test", code: 1) },
            fallback: -1, level: .warn)
        XCTAssertEqual(result, -1)
    }

    func testWithCatchHonorsErrorLevelOnFailure() async {
        let result = await AppErrorHandler.withCatch("Tag",
            fn: { throw NSError(domain: "test", code: 1) },
            fallback: "fallback", level: .error)
        XCTAssertEqual(result, "fallback")
    }

    // MARK: - withCatchSync

    func testWithCatchSyncReturnsValueOnHappyPath() {
        XCTAssertEqual(AppErrorHandler.withCatchSync("Tag", fn: { 5 }, fallback: 0), 5)
    }

    func testWithCatchSyncReturnsFallbackOnFailure() {
        XCTAssertEqual(AppErrorHandler.withCatchSync("Tag",
            fn: { throw NSError(domain: "x", code: 1) }, fallback: 0), 0)
    }

    // MARK: - classifyError

    func testClassifyErrorRecognizesDatabaseLockCodesAsRetryable() {
        let busy = ErrorInput(code: 5, message: "database is locked")
        let busyResult = AppErrorHandler.classifyError(busy)
        XCTAssertEqual(busyResult.category, .database)
        XCTAssertTrue(busyResult.isRetryable)

        let constraint = ErrorInput(code: 19, message: "constraint")
        let constraintResult = AppErrorHandler.classifyError(constraint)
        XCTAssertEqual(constraintResult.category, .database)
        XCTAssertFalse(constraintResult.isRetryable)
    }

    func testClassifyErrorRecognizesFilesystemENOENTAndFileErrors() {
        let byMsg = ErrorInput(code: -1, message: "ENOENT: file not found")
        XCTAssertEqual(AppErrorHandler.classifyError(byMsg).category, .filesystem)

        let mkdirErr = ErrorInput(code: -1, message: "mkdir failed")
        let mkdirResult = AppErrorHandler.classifyError(mkdirErr)
        XCTAssertEqual(mkdirResult.category, .filesystem)
        XCTAssertFalse(mkdirResult.isRetryable)
    }

    func testClassifyErrorRecognizesPermissionErrors() {
        // 1. 通过消息 'permission denied'
        let byMsg = ErrorInput(code: -1, message: "Permission denied by user")
        let byMsgResult = AppErrorHandler.classifyError(byMsg)
        XCTAssertEqual(byMsgResult.category, .permission)
        XCTAssertFalse(byMsgResult.isRetryable)
        // 2. 通过权限错误码区间
        let byCode = ErrorInput(code: 121, message: "permission not granted")
        XCTAssertEqual(AppErrorHandler.classifyError(byCode).category, .permission)
        // 3. 'not granted' 关键字
        let notGranted = ErrorInput(code: -1, message: "READ_IMAGEVIDEO not granted")
        XCTAssertEqual(AppErrorHandler.classifyError(notGranted).category, .permission)
    }

    func testClassifyErrorRecognizesMediaErrors() {
        let photoAsset = ErrorInput(code: -1, message: "photoAccessHelper fetch result failed")
        let result1 = AppErrorHandler.classifyError(photoAsset)
        XCTAssertEqual(result1.category, .media)
        XCTAssertTrue(result1.isRetryable)

        let pickerErr = ErrorInput(code: -1, message: "PhotoViewPicker photo select aborted")
        XCTAssertEqual(AppErrorHandler.classifyError(pickerErr).category, .media)
    }

    func testClassifyErrorRecognizesCancelErrors() {
        let byMsg = ErrorInput(code: -1, message: "Operation canceled by user")
        let result1 = AppErrorHandler.classifyError(byMsg)
        XCTAssertEqual(result1.category, .cancel)
        XCTAssertFalse(result1.isRetryable)

        let byCode = ErrorInput(code: 14000011, message: "user cancel")
        XCTAssertEqual(AppErrorHandler.classifyError(byCode).category, .cancel)

        let aborted = ErrorInput(code: -1, message: "request aborted")
        XCTAssertEqual(AppErrorHandler.classifyError(aborted).category, .cancel)
    }

    func testClassifyErrorRecognizesStorageErrors() {
        let byMsg = ErrorInput(code: -1, message: "disk full: no space left on device")
        let result1 = AppErrorHandler.classifyError(byMsg)
        XCTAssertEqual(result1.category, .storage)
        XCTAssertFalse(result1.isRetryable)

        let byCode = ErrorInput(code: 27, message: "ENOSPC")
        XCTAssertEqual(AppErrorHandler.classifyError(byCode).category, .storage)

        let quota = ErrorInput(code: -1, message: "quota exceeded")
        XCTAssertEqual(AppErrorHandler.classifyError(quota).category, .storage)
    }

    func testClassifyErrorRecognizesNetworkErrorsAnd5xxRetryability() {
        let serverErr = ErrorInput(code: 503, message: "unavailable")
        let serverResult = AppErrorHandler.classifyError(serverErr)
        XCTAssertEqual(serverResult.category, .network)
        XCTAssertTrue(serverResult.isRetryable)

        let clientErr = ErrorInput(code: 404, message: "not found")
        let clientResult = AppErrorHandler.classifyError(clientErr)
        XCTAssertEqual(clientResult.category, .network)
        XCTAssertFalse(clientResult.isRetryable)

        let byMsg = ErrorInput(code: -1, message: "socket timeout")
        XCTAssertEqual(AppErrorHandler.classifyError(byMsg).category, .network)
    }

    func testClassifyErrorRecognizesAiModelErrors() {
        let ai = ErrorInput(code: -1, message: "mindspore inference failed")
        XCTAssertEqual(AppErrorHandler.classifyError(ai).category, .ai)
    }

    func testClassifyErrorRecognizesValidationErrors() {
        let validation = ErrorInput(code: -1, message: "invalid format required")
        XCTAssertEqual(AppErrorHandler.classifyError(validation).category, .validation)
    }

    func testClassifyErrorFallsBackToUnknownCategory() {
        let unknown = ErrorInput(code: -1, message: "something else")
        let unknownResult = AppErrorHandler.classifyError(unknown)
        XCTAssertEqual(unknownResult.category, .unknown)
        XCTAssertFalse(unknownResult.isRetryable)
    }

    func testClassifyErrorToleratesStringCodesAndMissingMessages() {
        let stringCode = ErrorInput(code: "5", message: "busy")
        XCTAssertEqual(AppErrorHandler.classifyError(stringCode).category, .database)

        let noMessage = ErrorInput(code: 999)
        let noMessageResult = AppErrorHandler.classifyError(noMessage)
        XCTAssertEqual(noMessageResult.category, .unknown)
        XCTAssertEqual(noMessageResult.message, "")
    }

    // MARK: - classifyError（iOS NSError domain，L4）

    func testClassifyErrorPrefersNSPOSIXDomainOverCode() {
        // ENOSPC(28)：即使 message 含 "file" 也不应落 filesystem
        let enospc = ErrorInput(code: 28, message: "write file failed", domain: "NSPOSIXErrorDomain")
        let enospcResult = AppErrorHandler.classifyError(enospc)
        XCTAssertEqual(enospcResult.category, .storage)
        XCTAssertFalse(enospcResult.isRetryable)

        let eacces = ErrorInput(code: 13, message: "write file failed", domain: "NSPOSIXErrorDomain")
        XCTAssertEqual(AppErrorHandler.classifyError(eacces).category, .permission)

        let enoent = ErrorInput(code: 2, message: "read failed", domain: "NSPOSIXErrorDomain")
        XCTAssertEqual(AppErrorHandler.classifyError(enoent).category, .filesystem)
    }

    func testClassifyErrorRecognizesCocoaDomainCodes() {
        // NSFileWriteOutOfSpaceError
        let outOfSpace = ErrorInput(code: 516, message: "write failed", domain: "NSCocoaErrorDomain")
        let spaceResult = AppErrorHandler.classifyError(outOfSpace)
        XCTAssertEqual(spaceResult.category, .storage)

        // NSUserCancelledError
        let cancelled = ErrorInput(code: 3072, message: "user cancelled", domain: "NSCocoaErrorDomain")
        XCTAssertEqual(AppErrorHandler.classifyError(cancelled).category, .cancel)

        // NSFileNoSuchFileError
        let noSuchFile = ErrorInput(code: 4, message: "remove failed", domain: "NSCocoaErrorDomain")
        XCTAssertEqual(AppErrorHandler.classifyError(noSuchFile).category, .filesystem)

        // NSFileWriteNoPermissionError
        let noPerm = ErrorInput(code: 513, message: "write failed", domain: "NSCocoaErrorDomain")
        XCTAssertEqual(AppErrorHandler.classifyError(noPerm).category, .permission)

        // Core Data 持久化错误区间 → database 且可重试
        let coreData = ErrorInput(code: 134040, message: "persistent store failure", domain: "NSCocoaErrorDomain")
        let coreDataResult = AppErrorHandler.classifyError(coreData)
        XCTAssertEqual(coreDataResult.category, .database)
        XCTAssertTrue(coreDataResult.isRetryable)

        // 区间下/上边界（134000 存储类型错误 / 134110 元数据不匹配）
        let storeType = ErrorInput(code: 134000, message: "store type mismatch", domain: "NSCocoaErrorDomain")
        XCTAssertEqual(AppErrorHandler.classifyError(storeType).category, .database)
        let metadata = ErrorInput(code: 134110, message: "metadata mismatch", domain: "NSCocoaErrorDomain")
        XCTAssertEqual(AppErrorHandler.classifyError(metadata).category, .database)
        // 区间外（133999 / 134200）不误判
        let below = ErrorInput(code: 133999, message: "save failed", domain: "NSCocoaErrorDomain")
        XCTAssertNotEqual(AppErrorHandler.classifyError(below).category, .database)
    }

    func testClassifyErrorRecognizesPhotosAndURLErrorDomains() {
        let photos = ErrorInput(code: -1, message: "resource unavailable", domain: "PHPhotosErrorDomain")
        let photosResult = AppErrorHandler.classifyError(photos)
        XCTAssertEqual(photosResult.category, .media)
        XCTAssertTrue(photosResult.isRetryable)

        let timeout = ErrorInput(code: -1001, message: "timed out", domain: "NSURLErrorDomain")
        let timeoutResult = AppErrorHandler.classifyError(timeout)
        XCTAssertEqual(timeoutResult.category, .network)
        XCTAssertTrue(timeoutResult.isRetryable)

        let offline = ErrorInput(code: -1009, message: "offline", domain: "NSURLErrorDomain")
        XCTAssertFalse(AppErrorHandler.classifyError(offline).isRetryable)

        let swiftData = ErrorInput(code: 1, message: "save failed", domain: "SwiftDataErrorDomain")
        XCTAssertEqual(AppErrorHandler.classifyError(swiftData).category, .database)
    }

    func testClassifyErrorUnknownDomainFallsBackToMessageRules() {
        // 未命中已知域 → 回落原有 code/message 判定
        let unknownDomain = ErrorInput(code: 5, message: "database busy", domain: "CustomDomain")
        XCTAssertEqual(AppErrorHandler.classifyError(unknownDomain).category, .database)
    }

    // MARK: - ErrorCodeMap

    func testErrorCodeMapCoversAll10CategoriesWithStableEntries() {
        for cat in AppErrorCategory.allCases {
            let entry = errorCodeMap[cat.rawValue]
            XCTAssertNotNil(entry)
            XCTAssertTrue(entry!.defaultMessage.count > 0)
            XCTAssertTrue(entry!.level == .info || entry!.level == .warn || entry!.level == .error)
        }
    }

    func testErrorCodeMapDatabaseIsRetryableAndErrorLevel() {
        XCTAssertTrue(errorCodeMap[AppErrorCategory.database.rawValue]!.retryable)
        XCTAssertEqual(errorCodeMap[AppErrorCategory.database.rawValue]!.level, .error)
        XCTAssertTrue(errorCodeMap[AppErrorCategory.network.rawValue]!.retryable)
    }

    func testErrorCodeMapCancelIsNonRetryableAndInfoLevel() {
        XCTAssertFalse(errorCodeMap[AppErrorCategory.cancel.rawValue]!.retryable)
        XCTAssertEqual(errorCodeMap[AppErrorCategory.cancel.rawValue]!.level, .info)
    }

    func testErrorCodeMapStorageIsNonRetryableAndErrorLevel() {
        XCTAssertFalse(errorCodeMap[AppErrorCategory.storage.rawValue]!.retryable)
        XCTAssertEqual(errorCodeMap[AppErrorCategory.storage.rawValue]!.level, .error)
    }

    func testErrorCodeMapPermissionMediaAreWarnLevel() {
        XCTAssertEqual(errorCodeMap[AppErrorCategory.permission.rawValue]!.level, .warn)
        XCTAssertEqual(errorCodeMap[AppErrorCategory.media.rawValue]!.level, .warn)
        XCTAssertFalse(errorCodeMap[AppErrorCategory.permission.rawValue]!.retryable)
        XCTAssertTrue(errorCodeMap[AppErrorCategory.media.rawValue]!.retryable)
    }

    // MARK: - toUserMessage

    func testToUserMessageReturnsErrorCodeMapDefaultMessages() {
        let dbErr = ErrorInput(code: 5, message: "busy")
        XCTAssertEqual(AppErrorHandler.toUserMessage(dbErr),
                       errorCodeMap[AppErrorCategory.database.rawValue]!.defaultMessage)

        let permErr = ErrorInput(code: 121, message: "permission denied")
        XCTAssertEqual(AppErrorHandler.toUserMessage(permErr),
                       errorCodeMap[AppErrorCategory.permission.rawValue]!.defaultMessage)

        let mediaErr = ErrorInput(code: -1, message: "photoAccessHelper failed")
        XCTAssertEqual(AppErrorHandler.toUserMessage(mediaErr),
                       errorCodeMap[AppErrorCategory.media.rawValue]!.defaultMessage)

        let cancelErr = ErrorInput(code: 14000011, message: "canceled")
        XCTAssertEqual(AppErrorHandler.toUserMessage(cancelErr),
                       errorCodeMap[AppErrorCategory.cancel.rawValue]!.defaultMessage)

        let storageErr = ErrorInput(code: 27, message: "no space")
        XCTAssertEqual(AppErrorHandler.toUserMessage(storageErr),
                       errorCodeMap[AppErrorCategory.storage.rawValue]!.defaultMessage)

        let unknownErr = ErrorInput(code: 999, message: "mystery")
        XCTAssertEqual(AppErrorHandler.toUserMessage(unknownErr),
                       errorCodeMap[AppErrorCategory.unknown.rawValue]!.defaultMessage)
    }

    // MARK: - resolveLevel

    func testResolveLevelReturnsCorrectLevelForEachCategory() {
        let permErr = ErrorInput(code: 121, message: "permission denied")
        XCTAssertEqual(AppErrorHandler.resolveLevel(permErr), .warn)

        let cancelErr = ErrorInput(code: 14000011, message: "cancel")
        XCTAssertEqual(AppErrorHandler.resolveLevel(cancelErr), .info)

        let aiErr = ErrorInput(code: -1, message: "mindspore inference failed")
        XCTAssertEqual(AppErrorHandler.resolveLevel(aiErr), .warn)

        let storageErr = ErrorInput(code: 27, message: "ENOSPC")
        XCTAssertEqual(AppErrorHandler.resolveLevel(storageErr), .error)

        let dbErr = ErrorInput(code: 5, message: "busy")
        XCTAssertEqual(AppErrorHandler.resolveLevel(dbErr), .error)
    }

    // MARK: - sanitizeForLog 扩展规则

    func testSanitizeForLogRedactsUserAgentStringsStartingWithMozilla() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        let clean = AppErrorHandler.sanitizeForLog(ua)
        XCTAssertTrue(clean.contains("[UA]"))
    }

    func testSanitizeForLogRedactsLongBase64LikeStrings() {
        let longB64 = String(repeating: "Q", count: 64)
        let clean = AppErrorHandler.sanitizeForLog("embed=\(longB64) end")
        XCTAssertTrue(clean.contains("[B64]"))
        XCTAssertFalse(clean.contains(longB64))
    }

    func testSanitizeForLogDoesNotRedactShortBase64LikeStrings() {
        let short = "YWJjZA=="  // 'abcd' 的 base64
        let clean = AppErrorHandler.sanitizeForLog("token=\(short)")
        XCTAssertFalse(clean.contains("[B64]"))
    }

    func testSanitizeForLogRedactsStoragePaths() {
        let dirty = "open /storage/Users/currentUser/Documents/foo/bar.ms failed"
        let clean = AppErrorHandler.sanitizeForLog(dirty)
        XCTAssertFalse(clean.contains("/storage/Users/"))
        XCTAssertTrue(clean.contains("[PATH]"))
    }

    func testSanitizeForLogRedactsDatashareURIs() {
        let dirty = "read from datashare://media/photo/123?authority=abc"
        let clean = AppErrorHandler.sanitizeForLog(dirty)
        XCTAssertFalse(clean.contains("datashare://"))
        XCTAssertTrue(clean.contains("[URI]"))
    }

    func testSanitizeForLogRedactsDiagnosticsStringContainingSandboxModelPath() {
        let dirty = "loadModel: failed Error: open /data/storage/el2/base/haps/entry/clip_vision_encoder.ms EACCES"
        let clean = AppErrorHandler.sanitizeForLog(dirty)
        XCTAssertFalse(clean.contains("/data/storage/"))
        XCTAssertFalse(clean.contains("clip_vision_encoder.ms"))
        XCTAssertTrue(clean.contains("[PATH]"))
        XCTAssertTrue(clean.contains("loadModel"))
        XCTAssertTrue(clean.contains("EACCES"))
    }
}
