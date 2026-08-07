import XCTest
@testable import MiLensKit

/// DiagnosticsCollector 测试。翻译自源端 shared/.../test/DiagnosticsCollector.test.ets（24 用例）。
/// 覆盖 formatTimestamp、summarizeTaskCategories、buildDiagnosticsReport、defaultReportBaseName。
final class DiagnosticsCollectorTests: XCTestCase {

    private func makeSummary(_ kind: TaskKind, _ outcome: TaskOutcome, _ category: String,
                             _ elapsedMs: Int, _ stageCount: Int) -> FinishedTaskSummary {
        FinishedTaskSummary(kind: kind, outcome: outcome, category: category,
                            elapsedMs: elapsedMs, stageCount: stageCount)
    }

    private func makeInput() -> DiagnosticsInput {
        DiagnosticsInput(
            appVersionName: "1.0.0", appVersionCode: 1000000, bundleName: "com.milens.zhumie",
            sdkApiVersion: 21, distributionApiVersion: 50000, deviceType: "phone",
            dbVersion: 16, taskSummaries: [],
            aiDiagnostics: "AI has not run yet", visionDiagnostics: "CoreVision prefilter not run",
            cacheSizeText: "123.4 MB", generatedAtMs: 1721509800000)
    }

    /// 用 NSRegularExpression 验证格式（跨平台兼容）
    private func matchesPattern(_ s: String, _ pattern: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: s.utf16.count)
        return regex.firstMatch(in: s, range: range) != nil
    }

    // MARK: - formatTimestamp

    func testFormatsNormalTimestampIntoYyyyMMddHHmmssShape() {
        let s = formatTimestamp(1721509800000)
        XCTAssertTrue(matchesPattern(s, "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$"))
    }

    func testReturnsUnknownForNegativeTimestamp() {
        XCTAssertEqual(formatTimestamp(-1), "unknown")
    }

    func testReturnsUnknownForNaN() {
        XCTAssertEqual(formatTimestamp(.nan), "unknown")
    }

    func testReturnsUnknownForInfinity() {
        XCTAssertEqual(formatTimestamp(.infinity), "unknown")
    }

    func testFormatsEpochZeroWithoutThrowing() {
        let s = formatTimestamp(0)
        XCTAssertTrue(s.count > 0)
    }

    // MARK: - summarizeTaskCategories

    func testReturnsZeroStatsForEmptyArray() {
        let stats = summarizeTaskCategories([])
        XCTAssertEqual(stats.total, 0)
        XCTAssertEqual(stats.success, 0)
        XCTAssertEqual(stats.failed, 0)
        XCTAssertEqual(stats.canceled, 0)
        XCTAssertEqual(stats.failedByCategory.count, 0)
    }

    func testCountsOnlySuccessWhenAllSucceeded() {
        let arr = [
            makeSummary(.scan, .success, "None", 100, 3),
            makeSummary(.import_, .success, "None", 50, 1)
        ]
        let stats = summarizeTaskCategories(arr)
        XCTAssertEqual(stats.total, 2)
        XCTAssertEqual(stats.success, 2)
        XCTAssertEqual(stats.failed, 0)
        XCTAssertEqual(stats.canceled, 0)
        XCTAssertEqual(stats.failedByCategory.count, 0)
    }

    func testAggregatesFailuresByCategory() {
        let arr = [
            makeSummary(.scan, .failed, "DatabaseError", 100, 3),
            makeSummary(.import_, .failed, "DatabaseError", 50, 1),
            makeSummary(.backup, .failed, "NetworkError", 200, 2)
        ]
        let stats = summarizeTaskCategories(arr)
        XCTAssertEqual(stats.failed, 3)
        XCTAssertEqual(stats.failedByCategory.count, 2)
        // 按 count 降序：DatabaseError(2) 在前
        XCTAssertEqual(stats.failedByCategory[0].category, "DatabaseError")
        XCTAssertEqual(stats.failedByCategory[0].count, 2)
        XCTAssertEqual(stats.failedByCategory[1].category, "NetworkError")
        XCTAssertEqual(stats.failedByCategory[1].count, 1)
    }

    func testCountsSuccessFailedCanceledInMixedArray() {
        let arr = [
            makeSummary(.scan, .success, "None", 100, 3),
            makeSummary(.import_, .failed, "MediaError", 50, 1),
            makeSummary(.bead, .canceled, "None", 30, 0),
            makeSummary(.export, .failed, "PermissionError", 80, 2)
        ]
        let stats = summarizeTaskCategories(arr)
        XCTAssertEqual(stats.total, 4)
        XCTAssertEqual(stats.success, 1)
        XCTAssertEqual(stats.failed, 2)
        XCTAssertEqual(stats.canceled, 1)
        XCTAssertEqual(stats.failedByCategory.count, 2)
    }

    func testTreatsEmptyStringCategoryAsNonePlaceholder() {
        let arr = [makeSummary(.scan, .failed, "", 100, 1)]
        let stats = summarizeTaskCategories(arr)
        XCTAssertEqual(stats.failed, 1)
        XCTAssertEqual(stats.failedByCategory.count, 1)
        XCTAssertEqual(stats.failedByCategory[0].category, "None")
    }

    // MARK: - buildDiagnosticsReport

    func testContainsAppVersionAndBundleName() {
        let report = buildDiagnosticsReport(makeInput())
        XCTAssertTrue(report.contains("1.0.0"))
        XCTAssertTrue(report.contains("1000000"))
        XCTAssertTrue(report.contains("com.milens.zhumie"))
    }

    func testContainsDeviceApiLevelAndDeviceType() {
        let report = buildDiagnosticsReport(makeInput())
        XCTAssertTrue(report.contains("API Level：21"))
        XCTAssertTrue(report.contains("phone"))
    }

    func testContainsDbVersion() {
        var input = makeInput()
        input.dbVersion = 16
        let report = buildDiagnosticsReport(input)
        XCTAssertTrue(report.contains("版本：16"))
    }

    func testShowsZeroCountStatsWhenNoTaskSummaries() {
        let report = buildDiagnosticsReport(makeInput())
        XCTAssertTrue(report.contains("总数：0"))
        XCTAssertTrue(report.contains("成功：0"))
        XCTAssertTrue(report.contains("失败：0"))
    }

    func testShowsFailureCategoriesWhenTasksFailed() {
        var input = makeInput()
        input.taskSummaries = [
            makeSummary(.scan, .failed, "DatabaseError", 100, 3),
            makeSummary(.import_, .success, "None", 50, 1)
        ]
        let report = buildDiagnosticsReport(input)
        XCTAssertTrue(report.contains("失败：1"))
        XCTAssertTrue(report.contains("成功：1"))
        XCTAssertTrue(report.contains("DatabaseError：1"))
    }

    func testShowsPlaceholderWhenAiDiagnosticsIsEmpty() {
        var input = makeInput()
        input.aiDiagnostics = ""
        let report = buildDiagnosticsReport(input)
        XCTAssertTrue(report.contains("（未运行）"))
    }

    func testShowsPlaceholderWhenVisionDiagnosticsIsEmpty() {
        var input = makeInput()
        input.visionDiagnostics = ""
        let report = buildDiagnosticsReport(input)
        XCTAssertTrue(report.contains("（未运行）"))
    }

    func testIncludesPrivacyFooter() {
        let report = buildDiagnosticsReport(makeInput())
        XCTAssertTrue(report.contains("隐私说明"))
        XCTAssertTrue(report.contains("不包含照片"))
    }

    func testRedactsContentURIInAiDiagnostics() {
        var input = makeInput()
        input.aiDiagnostics = "loadModel: opened content://media/external/images/123"
        let report = buildDiagnosticsReport(input)
        XCTAssertFalse(report.contains("content://media/external/images/123"))
        XCTAssertTrue(report.contains("[URI]"))
    }

    func testRedactsDataStoragePathInVisionDiagnostics() {
        var input = makeInput()
        input.visionDiagnostics = "prefilter path=/data/storage/el2/abc/photo.jpg"
        let report = buildDiagnosticsReport(input)
        XCTAssertFalse(report.contains("/data/storage/el2/abc/photo.jpg"))
        XCTAssertTrue(report.contains("[PATH]"))
    }

    func testRedactsIPv4AddressInBundleNameField() {
        var input = makeInput()
        input.bundleName = "conn from 192.168.1.100 ok"
        let report = buildDiagnosticsReport(input)
        XCTAssertFalse(report.contains("192.168.1.100"))
        XCTAssertTrue(report.contains("[IP]"))
    }

    func testRedactsTokenLikeSecretInCacheSizeText() {
        var input = makeInput()
        input.cacheSizeText = "token=abc123secret456 size=10MB"
        let report = buildDiagnosticsReport(input)
        XCTAssertFalse(report.contains("abc123secret456"))
        XCTAssertTrue(report.contains("[REDACTED]"))
    }

    // MARK: - defaultReportBaseName

    func testProducesMilensDiagnosticsYyyyMMddHHmmssShape() {
        let name = defaultReportBaseName(makeInput())
        XCTAssertTrue(matchesPattern(name, "^milens-diagnostics-\\d{8}-\\d{6}$"))
    }

    func testStartsWithMilensDiagnosticsPrefix() {
        let name = defaultReportBaseName(makeInput())
        XCTAssertTrue(name.hasPrefix("milens-diagnostics-"))
    }
}
