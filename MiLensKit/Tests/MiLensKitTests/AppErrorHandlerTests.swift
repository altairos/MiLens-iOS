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
