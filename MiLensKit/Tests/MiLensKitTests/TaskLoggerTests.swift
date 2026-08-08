import XCTest
@testable import MiLensKit

/// TaskLogger 测试。翻译自源端 shared/.../test/TaskLogger.test.ets（27 用例）。
/// 每用例前 resetForTest 保证 taskId 从 1 开始递增。
final class TaskLoggerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TaskLogger.resetForTest()
    }

    // MARK: - beginTask

    func testBeginTaskReturnsIncrementingPositiveTaskIds() {
        let id1 = TaskLogger.beginTask(.scan, label: "full")
        let id2 = TaskLogger.beginTask(.import_, label: "manual")
        let id3 = TaskLogger.beginTask(.bead)
        XCTAssertTrue(id1 > 0)
        XCTAssertTrue(id2 > id1)
        XCTAssertTrue(id3 > id2)
        TaskLogger.complete(id1, summary: "done1")
        TaskLogger.complete(id2, summary: "done2")
        TaskLogger.complete(id3, summary: "done3")
    }

    func testBeginTaskWithNoLabelStillCreatesActiveTask() {
        let taskId = TaskLogger.beginTask(.export)
        XCTAssertTrue(taskId > 0)
        XCTAssertTrue(TaskLogger.isActive(taskId))
        TaskLogger.complete(taskId)
    }

    // MARK: - isActive

    func testIsActiveReturnsFalseForInvalidTaskIdZero() {
        XCTAssertFalse(TaskLogger.isActive(0))
    }

    func testIsActiveReturnsFalseForUnknownTaskId() {
        XCTAssertFalse(TaskLogger.isActive(99999))
    }

    // MARK: - stage

    func testStageOnActiveTaskDoesNotThrowAndIncrementsStageCount() {
        let taskId = TaskLogger.beginTask(.scan, label: "full")
        TaskLogger.stage(taskId, "detect")
        TaskLogger.stage(taskId, "match")
        TaskLogger.stage(taskId, "quality")
        XCTAssertTrue(TaskLogger.isActive(taskId))
        TaskLogger.complete(taskId, summary: "matched=5")
        XCTAssertFalse(TaskLogger.isActive(taskId))
    }

    func testStageOnUnknownTaskIdIsSilentlyIgnored() {
        TaskLogger.stage(99999, "whatever")
        TaskLogger.stage(99999, "next", detail: "detail")
    }

    // MARK: - progress

    func testProgressRecordsCurrentTotalWithoutThrowing() {
        let taskId = TaskLogger.beginTask(.import_, label: "batch")
        TaskLogger.progress(taskId, current: 10, total: 100)
        TaskLogger.progress(taskId, current: 50, total: 100)
        TaskLogger.complete(taskId, summary: "imported=100")
    }

    func testProgressWithTotalZeroOnlyRecordsCurrent() {
        let taskId = TaskLogger.beginTask(.bead)
        TaskLogger.progress(taskId, current: 5, total: 0)
        TaskLogger.complete(taskId, summary: "ok")
    }

    // MARK: - complete / cancel / fail

    func testCompleteRemovesTaskFromActiveSet() {
        let taskId = TaskLogger.beginTask(.backup, label: "port=8080")
        XCTAssertTrue(TaskLogger.isActive(taskId))
        TaskLogger.complete(taskId, summary: "sent=12")
        XCTAssertFalse(TaskLogger.isActive(taskId))
    }

    func testCancelIsEquivalentToCompleteCanceled() {
        let taskId = TaskLogger.beginTask(.scan)
        TaskLogger.cancel(taskId, summary: "user-canceled")
        XCTAssertFalse(TaskLogger.isActive(taskId))
    }

    func testFailRemovesTaskAndClassifiesError() {
        let taskId = TaskLogger.beginTask(.scan)
        let dbErr = ErrorInput(code: 5, message: "database busy")
        TaskLogger.fail(taskId, err: dbErr)
        XCTAssertFalse(TaskLogger.isActive(taskId))
    }

    func testFailWithPermissionErrorDoesNotCrash() {
        let taskId = TaskLogger.beginTask(.import_)
        let permErr = ErrorInput(code: 121, message: "permission denied")
        TaskLogger.fail(taskId, err: permErr)
        XCTAssertFalse(TaskLogger.isActive(taskId))
    }

    func testFailWithUnknownTaskIdIsSilentlyIgnored() {
        let err = ErrorInput(code: 5, message: "busy")
        TaskLogger.fail(99999, err: err)
    }

    func testCompleteOnAlreadyCompletedTaskIdIsIdempotent() {
        let taskId = TaskLogger.beginTask(.export)
        TaskLogger.complete(taskId, summary: "done=10")
        XCTAssertFalse(TaskLogger.isActive(taskId))
        // 重复 complete 不应抛错
        TaskLogger.complete(taskId, summary: "repeat")
        TaskLogger.complete(taskId)
    }

    func testCancelOnUnknownTaskIdIsSilentlyIgnored() {
        TaskLogger.cancel(99999, summary: "nope")
    }

    func testProgressOnUnknownTaskIdIsSilentlyIgnored() {
        TaskLogger.progress(99999, current: 1, total: 10)
    }

    // MARK: - sanitize

    func testLabelContainingURIIsSanitizedToURI() {
        let taskId = TaskLogger.beginTask(.scan, label: "content://media/external/images/123")
        XCTAssertTrue(taskId > 0)
        TaskLogger.stage(taskId, "detect", detail: "file:///data/storage/el2/abc")
        TaskLogger.complete(taskId, summary: "ok")
    }

    func testStageDetailContainingPathIsSanitized() {
        let taskId = TaskLogger.beginTask(.backup)
        TaskLogger.stage(taskId, "zipping", detail: "path=/data/storage/el2/123/photos")
        TaskLogger.complete(taskId, summary: "sent=5")
    }

    // MARK: - 五种 TaskKind

    func testAllFiveTaskKindsCanBeStartedAndCompleted() {
        let scan = TaskLogger.beginTask(.scan)
        let imp = TaskLogger.beginTask(.import_)
        let bead = TaskLogger.beginTask(.bead)
        let backup = TaskLogger.beginTask(.backup)
        let exp = TaskLogger.beginTask(.export)
        XCTAssertTrue(scan > 0 && imp > 0 && bead > 0 && backup > 0 && exp > 0)
        TaskLogger.complete(scan, summary: "s")
        TaskLogger.complete(imp, summary: "i")
        TaskLogger.complete(bead, summary: "b")
        TaskLogger.complete(backup, summary: "k")
        TaskLogger.complete(exp, summary: "e")
    }

    // MARK: - getRecentSummaries

    func testGetRecentSummariesReturnsEmptyArrayWhenNoTasksFinished() {
        let arr = TaskLogger.getRecentSummaries()
        XCTAssertEqual(arr.count, 0)
    }

    func testGetRecentSummariesRecordsCompletedTaskWithSuccessOutcome() {
        let taskId = TaskLogger.beginTask(.scan, label: "full")
        TaskLogger.stage(taskId, "detect")
        TaskLogger.stage(taskId, "match")
        TaskLogger.complete(taskId, summary: "matched=5")
        let arr = TaskLogger.getRecentSummaries()
        XCTAssertEqual(arr.count, 1)
        XCTAssertEqual(arr[0].kind, .scan)
        XCTAssertEqual(arr[0].outcome, .success)
        XCTAssertEqual(arr[0].category, TASK_CATEGORY_NONE)
        XCTAssertEqual(arr[0].stageCount, 2)
        XCTAssertGreaterThanOrEqual(arr[0].elapsedMs, 0)
    }

    func testGetRecentSummariesRecordsFailedTaskWithErrorCategory() {
        let taskId = TaskLogger.beginTask(.import_)
        let dbErr = ErrorInput(code: 5, message: "database busy")
        TaskLogger.fail(taskId, err: dbErr)
        let arr = TaskLogger.getRecentSummaries()
        XCTAssertEqual(arr.count, 1)
        XCTAssertEqual(arr[0].outcome, .failed)
        XCTAssertEqual(arr[0].category, AppErrorCategory.database.rawValue)
    }

    func testGetRecentSummariesRecordsCanceledTaskOutcome() {
        let taskId = TaskLogger.beginTask(.backup)
        TaskLogger.cancel(taskId, summary: "user-canceled")
        let arr = TaskLogger.getRecentSummaries()
        XCTAssertEqual(arr.count, 1)
        XCTAssertEqual(arr[0].outcome, .canceled)
        XCTAssertEqual(arr[0].category, TASK_CATEGORY_NONE)
    }

    func testGetRecentSummariesPreservesFinishOrderFIFO() {
        let t1 = TaskLogger.beginTask(.scan)
        let t2 = TaskLogger.beginTask(.import_)
        let t3 = TaskLogger.beginTask(.bead)
        TaskLogger.complete(t1)
        TaskLogger.complete(t2)
        TaskLogger.complete(t3)
        let arr = TaskLogger.getRecentSummaries()
        XCTAssertEqual(arr.count, 3)
        XCTAssertEqual(arr[0].kind, .scan)
        XCTAssertEqual(arr[1].kind, .import_)
        XCTAssertEqual(arr[2].kind, .bead)
    }

    func testGetRecentSummariesCapsAt50EntriesFIFOEviction() {
        // 连续创建并完成 55 个任务
        for _ in 0..<55 {
            let id = TaskLogger.beginTask(.scan)
            TaskLogger.complete(id)
        }
        let arr = TaskLogger.getRecentSummaries()
        XCTAssertEqual(arr.count, 50)
    }

    func testGetRecentSummariesReturnsACopyMutationDoesNotAffectInternalState() {
        let taskId = TaskLogger.beginTask(.scan)
        TaskLogger.complete(taskId)
        var arr1 = TaskLogger.getRecentSummaries()
        // 修改返回的数组
        arr1.removeAll()
        arr1.append(FinishedTaskSummary(kind: .export, outcome: .success,
                                         category: "fake", elapsedMs: 0, stageCount: 0))
        // 再次获取不受影响
        let arr2 = TaskLogger.getRecentSummaries()
        XCTAssertEqual(arr2.count, 1)
        XCTAssertEqual(arr2[0].kind, .scan)
    }

    func testGetRecentSummariesDoesNotContainLabelDetailPrivacy() {
        let taskId = TaskLogger.beginTask(.scan, label: "content://media/secret/123")
        TaskLogger.stage(taskId, "detect", detail: "file:///data/storage/el2/secret/photo.jpg")
        TaskLogger.complete(taskId, summary: "matched=5")
        let arr = TaskLogger.getRecentSummaries()
        // 摘要只包含 kind/outcome/category/elapsedMs/stageCount，不含 label/detail
        XCTAssertEqual(arr.count, 1)
        let mirrorChildren = Mirror(reflecting: arr[0]).children.compactMap { $0.label }
        XCTAssertFalse(mirrorChildren.contains("label"))
        XCTAssertFalse(mirrorChildren.contains("detail"))
    }
}
