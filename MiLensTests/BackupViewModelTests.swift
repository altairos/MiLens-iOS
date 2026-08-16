//  BackupViewModelTests —— 离线备份 ViewModel 状态机测试。
//  覆盖：服务可用性透传、预估（成功/失败/estimating 中重复触发忽略）、
//  导出（进度回调、成功记录 lastBackupDate、失败不记录）、
//  恢复（成功统计/失败/导出进行中互斥忽略）、状态复位、
//  距上次备份天数读取注入的 UserDefaults suite。

import XCTest
@testable import MiLens

/// BackupService mock：可预设结果/错误/进度序列；
/// 可在预估或导出处挂起，构造「进行中」并发窗口以验证幂等/互斥 guard。
@MainActor
private final class MockBackupService: BackupService {
    var stubbedIsAvailable = true
    var estimate = BackupEstimate(petCount: 2, photoCount: 10, estimatedBytes: 2048)
    var estimateError: Error?
    var exportError: Error?
    var exportResult: BackupResult?
    var restoreResult = RestoreResult(importedPets: 1, importedPhotos: 5, importedEvents: 2, skipped: 1)
    var restoreError: Error?
    /// 导出时依次回调的进度序列（在挂起前推送）。
    var exportProgresses: [BackupProgress] = []
    /// 为 true 时在推送进度后挂起，直到 releaseExport()。
    var holdExport = false
    /// 为 true 时在计数后挂起，直到 releaseEstimate()。
    var holdEstimate = false

    private(set) var estimateCallCount = 0
    private(set) var exportCallCount = 0
    private(set) var importCallCount = 0
    private(set) var lastImportedURLs: [URL]?

    private var estimateWaiters: [CheckedContinuation<Void, Never>] = []
    private var exportWaiters: [CheckedContinuation<Void, Never>] = []

    var isAvailable: Bool { stubbedIsAvailable }

    func estimateBackup(petIDs: [UUID]?) async throws -> BackupEstimate {
        estimateCallCount += 1
        if holdEstimate {
            await withCheckedContinuation { estimateWaiters.append($0) }
        }
        if let estimateError { throw estimateError }
        return estimate
    }

    func exportBackup(
        petIDs: [UUID]?,
        progress: @escaping @Sendable @MainActor (BackupProgress) -> Void
    ) async throws -> BackupResult {
        exportCallCount += 1
        for p in exportProgresses { progress(p) }
        if holdExport {
            await withCheckedContinuation { exportWaiters.append($0) }
        }
        if let exportError { throw exportError }
        return exportResult ?? BackupResult(
            fileURLs: [URL(fileURLWithPath: "/tmp/milens-backup.milensbackup")],
            manifest: BackupManifest(
                schemaVersion: BackupConfig.currentSchemaVersion,
                appVersion: "1.0", platform: "ios",
                exportDate: Date(timeIntervalSince1970: 0), photoCount: 10, petCount: 2),
            metadata: BackupMetadata(pets: [], photos: [], petEvents: [])
        )
    }

    func importBackup(
        from urls: [URL],
        progress: @escaping @Sendable @MainActor (RestoreProgress) -> Void
    ) async throws -> RestoreResult {
        importCallCount += 1
        lastImportedURLs = urls
        progress(RestoreProgress(current: 3, total: 3, phase: .done))
        if let restoreError { throw restoreError }
        return restoreResult
    }

    func releaseEstimate() {
        estimateWaiters.forEach { $0.resume() }
        estimateWaiters = []
    }

    func releaseExport() {
        exportWaiters.forEach { $0.resume() }
        exportWaiters = []
    }
}

@MainActor
final class BackupViewModelTests: XCTestCase {

    /// 独立 UserDefaults suite：构造时清空保证起点干净，测试结束移除持久化域。
    private func makeDefaults() throws -> UserDefaults {
        let name = "MiLens.BackupViewModelTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forDomainName: name)
        addTeardownBlock { defaults.removePersistentDomain(forDomainName: name) }
        return defaults
    }

    /// 轮询等待条件成立（主线程让出，最多 ~2.5s）。
    private func waitUntil(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - 服务可用性

    func testIsServiceAvailableReflectsService() throws {
        let defaults = try makeDefaults()
        let service = MockBackupService()
        let vm = BackupViewModel(backupService: service, defaults: defaults)

        XCTAssertTrue(vm.isServiceAvailable)
        service.stubbedIsAvailable = false
        XCTAssertFalse(vm.isServiceAvailable)
    }

    // MARK: - 预估

    func testPrepareExportPublishesEstimate() throws {
        let defaults = try makeDefaults()
        let service = MockBackupService()
        service.estimate = BackupEstimate(petCount: 3, photoCount: 42, estimatedBytes: 999)
        let vm = BackupViewModel(backupService: service, defaults: defaults)

        await vm.prepareExport()

        XCTAssertEqual(vm.exportState, .readyToExport(service.estimate))
        XCTAssertEqual(service.estimateCallCount, 1)
    }

    func testPrepareExportFailureProducesFailedState() throws {
        let defaults = try makeDefaults()
        let service = MockBackupService()
        service.estimateError = BackupServiceError.serviceUnavailable
        let vm = BackupViewModel(backupService: service, defaults: defaults)

        await vm.prepareExport()

        XCTAssertEqual(
            vm.exportState,
            .failed(BackupServiceError.serviceUnavailable.localizedDescription))
    }

    func testPrepareExportIgnoredWhileEstimating() throws {
        let defaults = try makeDefaults()
        let service = MockBackupService()
        service.holdEstimate = true
        let vm = BackupViewModel(backupService: service, defaults: defaults)

        let first = Task { await vm.prepareExport() }
        await waitUntil(vm.isEstimating)

        // estimating 进行中重复触发：guard 直接忽略
        await vm.prepareExport()
        XCTAssertEqual(service.estimateCallCount, 1, "预估进行中重复触发应被忽略")

        service.releaseEstimate()
        _ = await first.value
        XCTAssertEqual(vm.exportState, .readyToExport(service.estimate))
    }

    // MARK: - 导出

    func testExportBackupRecordsLastBackupDateAndDone() throws {
        let defaults = try makeDefaults()
        let service = MockBackupService()
        service.exportProgresses = [
            BackupProgress(current: 0, total: 10, phase: .collectingMetadata),
            BackupProgress(current: 5, total: 10, phase: .copyingPhotos),
            BackupProgress(current: 10, total: 10, phase: .done)
        ]
        let vm = BackupViewModel(backupService: service, defaults: defaults)
        XCTAssertNil(vm.lastBackupDate, "测试 suite 起点应无备份记录")

        await vm.exportBackup()

        let expectedURL = URL(fileURLWithPath: "/tmp/milens-backup.milensbackup")
        XCTAssertEqual(vm.exportState, .done([expectedURL]))
        let recorded = try XCTUnwrap(vm.lastBackupDate, "导出成功应记录备份时间")
        XCTAssertLessThan(Date().timeIntervalSince(recorded), 60)
        XCTAssertEqual(service.exportCallCount, 1)
    }

    func testExportBackupFailureSkipsLastBackupDate() throws {
        let defaults = try makeDefaults()
        let service = MockBackupService()
        service.exportError = BackupServiceError.backupFailed("disk full")
        let vm = BackupViewModel(backupService: service, defaults: defaults)

        await vm.exportBackup()

        XCTAssertEqual(vm.exportState, .failed(BackupServiceError.backupFailed("disk full").localizedDescription))
        XCTAssertNil(vm.lastBackupDate, "导出失败不应记录备份时间")
    }

    // MARK: - 恢复

    func testImportBackupPublishesRestoreStats() throws {
        let defaults = try makeDefaults()
        let service = MockBackupService()
        let vm = BackupViewModel(backupService: service, defaults: defaults)
        let urls = [URL(fileURLWithPath: "/tmp/volume-1.milensbackup")]

        await vm.importBackup(from: urls)

        XCTAssertEqual(vm.restoreState, .done(service.restoreResult))
        XCTAssertEqual(service.lastImportedURLs, urls)
    }

    func testImportBackupFailureProducesFailedState() throws {
        let defaults = try makeDefaults()
        let service = MockBackupService()
        service.restoreError = BackupServiceError.invalidFormat
        let vm = BackupViewModel(backupService: service, defaults: defaults)

        await vm.importBackup(from: [URL(fileURLWithPath: "/tmp/bad.milensbackup")])

        XCTAssertEqual(
            vm.restoreState,
            .failed(BackupServiceError.invalidFormat.localizedDescription))
    }

    func testImportBackupIgnoredWhileExporting() throws {
        let defaults = try makeDefaults()
        let service = MockBackupService()
        service.holdExport = true
        service.exportProgresses = [BackupProgress(current: 5, total: 10, phase: .copyingPhotos)]
        let vm = BackupViewModel(backupService: service, defaults: defaults)

        let exportTask = Task { await vm.exportBackup() }
        // 等待进度回调落地（验证进度闭包写入导出中状态）
        await waitUntil(vm.exportState == .inProgress(0.5, .copyingPhotos))
        XCTAssertEqual(vm.exportState, .inProgress(0.5, .copyingPhotos))

        // 导出进行中触发恢复：互斥 guard 直接忽略
        await vm.importBackup(from: [URL(fileURLWithPath: "/tmp/v.milensbackup")])
        XCTAssertEqual(service.importCallCount, 0, "导出进行中恢复应被互斥忽略")

        service.releaseExport()
        _ = await exportTask.value
        if case .done = vm.exportState {} else {
            XCTFail("放行后导出应完成，实际：\(vm.exportState)")
        }
    }

    // MARK: - 状态复位

    func testResetStatesReturnToIdle() throws {
        let defaults = try makeDefaults()
        let service = MockBackupService()
        let vm = BackupViewModel(backupService: service, defaults: defaults)

        await vm.prepareExport()
        XCTAssertEqual(vm.exportState, .readyToExport(service.estimate))
        vm.resetExport()
        XCTAssertEqual(vm.exportState, .idle)

        await vm.importBackup(from: [])
        if case .done = vm.restoreState {} else {
            XCTFail("恢复应完成，实际：\(vm.restoreState)")
        }
        vm.resetRestore()
        XCTAssertEqual(vm.restoreState, .idle)
    }

    // MARK: - 距上次备份天数

    func testDaysSinceLastBackupReadsInjectedDefaults() throws {
        let defaults = try makeDefaults()
        let vm = BackupViewModel(backupService: MockBackupService(), defaults: defaults)

        XCTAssertNil(vm.daysSinceLastBackup, "从未备份应返回 nil")

        let fiveDaysAgo = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: -5, to: Date()))
        defaults.set(fiveDaysAgo, forKey: BackupViewModel.lastBackupDateKey)
        XCTAssertEqual(vm.daysSinceLastBackup, 5)
    }
}
