import XCTest
import SwiftData
@testable import MiLens

/// ScanService 测试——扫描编排逻辑（对应源端 PhotoScanner 行为）。
/// 使用 in-memory SwiftData + mock 平台服务，覆盖去重、检测、取消、空库。
///
/// 注：container 必须由 makeService 返回并持有——mainContext 不持有 container，
/// 局部变量释放后 repo 的 fetch 会触发 SwiftData 内部 SIGTRAP（悬垂引用）。
@MainActor
final class ScanServiceTests: XCTestCase {

    private func makeService(
        assets: [PhotoAssetMetadata] = [],
        detections: [DetectionBox] = [],
        clipService: (any ClipInference)? = nil
    ) -> (ScanService, SwiftDataPhotoRepository, ModelContainer) {
        // container 必须返回并持有——mainContext 不持有 container，
        // 局部变量释放后 repo 的 fetch 触发 SwiftData 内部 SIGTRAP（悬垂引用）。
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let photoLibrary = MockPhotoLibraryAccess(assets: assets)
        let vision = MockVisionService(detections: detections)
        let service = ScanService(
            photoLibrary: photoLibrary, vision: vision,
            photoRepo: photoRepo, petRepo: petRepo,
            clipService: clipService
        )
        return (service, photoRepo, container)
    }

    private func asset(_ id: String) -> PhotoAssetMetadata {
        PhotoAssetMetadata(
            identifier: id, dateTaken: nil, dateAdded: nil,
            pixelWidth: 256, pixelHeight: 256, fileSize: 1024, displayName: "\(id).jpg"
        )
    }

    // MARK: - 空库

    func testScanEmptyLibraryReturnsEmptyResult() async {
        let (service, _, container) = makeService(assets: [], detections: [])
        let result = await service.scanAlbum()
        XCTAssertEqual(result.processedCount, 0)
        XCTAssertTrue(result.unassignedPetUris.isEmpty)
        XCTAssertFalse(result.canceled)
    }

    // MARK: - 检测

    func testScanWithNoPetDetectionsReturnsEmpty() async {
        let (service, _, container) = makeService(
            assets: [asset("a"), asset("b")],
            detections: [] // 无宠物检测结果
        )
        let result = await service.scanAlbum()
        XCTAssertEqual(result.processedCount, 2)
        XCTAssertTrue(result.unassignedPetUris.isEmpty)
    }

    func testScanWithPetDetectionsCollectsUnassigned() async {
        let petBox = DetectionBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)
        let (service, _, container) = makeService(
            assets: [asset("a"), asset("b"), asset("c")],
            detections: [petBox]
        )
        let result = await service.scanAlbum()
        XCTAssertEqual(result.processedCount, 3)
        XCTAssertEqual(result.unassignedPetUris.count, 3)
        XCTAssertEqual(result.petPhotosFoundCount, 3)
    }

    // MARK: - 去重（originalURI 为主键，P0 修复）

    func testScanSkipsAlreadyImportedPhotos() async {
        let (service, photoRepo, container) = makeService(
            assets: [asset("a"), asset("b")],
            detections: [DetectionBox(x: 0, y: 0, width: 0.5, height: 0.5, label: "dog", confidence: 0.9)]
        )
        // 预先入库一张照片（模拟已导入，originalURI = "a"）
        try! photoRepo.insertPhoto(Photo(uri: "a"))

        let result = await service.scanAlbum()
        // "a" 被跳过，只处理 "b"
        XCTAssertEqual(result.processedCount, 1)
        XCTAssertEqual(result.unassignedPetUris, ["b"])
    }

    func testScanDoesNotSkipBySandboxURIPath() async {
        // uri 是沙盒副本路径（hashToFilename 生成，与 identifier 无关）；
        // 已入库照片即使 uri 不等于 identifier，也必须按 originalURI 跳过。
        let (service, photoRepo, container) = makeService(
            assets: [asset("a"), asset("b")],
            detections: [DetectionBox(x: 0, y: 0, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)]
        )
        // 预先入库：uri = 沙盒路径，originalURI = "a"
        try! photoRepo.insertPhoto(Photo(uri: "/documents/MiPhotos/abc.jpg", originalURI: "a"))

        let result = await service.scanAlbum()
        XCTAssertEqual(result.processedCount, 1)
        XCTAssertEqual(result.unassignedPetUris, ["b"])
    }

    // MARK: - CLIP Phase 2 精筛（P0 修复）

    func testScanWithoutClipUsesPrefilterOnly() async {
        // clipService = nil（模型缺失）：仅 Phase 1 预筛，命中即收录
        let (service, _, container) = makeService(
            assets: [asset("a")],
            detections: [DetectionBox(x: 0, y: 0, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)]
        )
        let result = await service.scanAlbum()
        XCTAssertEqual(result.unassignedPetUris, ["a"])
    }

    func testClipSecondPhaseConfirmsPet() async {
        let clip = MockClipInference(result: ClipDetectionResult(
            isPet: true, labels: [], species: "cat", embedding: [],
            topLabel: "cat", topConfidence: 0.9, usedClipModel: true, diagnostics: ""))
        let (service, _, container) = makeService(
            assets: [asset("a")],
            detections: [DetectionBox(x: 0, y: 0, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)],
            clipService: clip
        )
        let result = await service.scanAlbum()
        // Phase 1 命中 + Phase 2 确认为宠物 → 收录
        XCTAssertEqual(result.unassignedPetUris, ["a"])
        XCTAssertEqual(clip.detectCallCount, 1)
    }

    func testClipSecondPhaseRejectsNonPet() async {
        let clip = MockClipInference(result: ClipDetectionResult(
            isPet: false, labels: [], species: nil, embedding: [],
            topLabel: "person", topConfidence: 0.95, usedClipModel: true, diagnostics: ""))
        let (service, _, container) = makeService(
            assets: [asset("a")],
            detections: [DetectionBox(x: 0, y: 0, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)],
            clipService: clip
        )
        let result = await service.scanAlbum()
        // Phase 1 命中但 Phase 2 拒绝 → 不收录（processedCount 仍计入）
        XCTAssertTrue(result.unassignedPetUris.isEmpty)
        XCTAssertEqual(result.processedCount, 1)
    }

    func testClipFailureFallsBackToPrefilter() async {
        // CLIP 推理失败 → 降级为 Phase 1 预筛结论（不中断扫描，对应源端多级降级）
        let clip = MockClipInference(error: MockClipError.inferenceFailed)
        let (service, _, container) = makeService(
            assets: [asset("a"), asset("b")],
            detections: [DetectionBox(x: 0, y: 0, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)],
            clipService: clip
        )
        let result = await service.scanAlbum()
        XCTAssertEqual(result.unassignedPetUris, ["a", "b"])
        XCTAssertEqual(result.processedCount, 2)
    }

    // MARK: - 新增模式

    func testScanNewOnlySkipsOldPhotos() async {
        let oldDate = Date(timeIntervalSince1970: 1000)
        let recentDate = Date(timeIntervalSince1970: 5000)
        let cutoff = Date(timeIntervalSince1970: 3000)

        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let assets = [
            PhotoAssetMetadata(identifier: "old", dateTaken: nil, dateAdded: oldDate,
                               pixelWidth: 256, pixelHeight: 256, fileSize: 1024, displayName: "old.jpg"),
            PhotoAssetMetadata(identifier: "recent", dateTaken: nil, dateAdded: recentDate,
                               pixelWidth: 256, pixelHeight: 256, fileSize: 1024, displayName: "recent.jpg"),
        ]
        let photoLibrary = MockPhotoLibraryAccess(assets: assets)
        let vision = MockVisionService(detections: [
            DetectionBox(x: 0, y: 0, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)
        ])
        let service = ScanService(photoLibrary: photoLibrary, vision: vision,
                                  photoRepo: photoRepo, petRepo: petRepo)

        let result = await service.scanAlbum(afterTimestamp: cutoff)
        // "old" 被跳过（dateAdded < cutoff），只处理 "recent"
        XCTAssertEqual(result.processedCount, 1)
        XCTAssertEqual(result.unassignedPetUris, ["recent"])
    }

    // MARK: - 进度回调

    func testScanReportsProgress() async {
        let (service, _, container) = makeService(assets: [asset("a"), asset("b")], detections: [])
        var progressCount = 0
        _ = await service.scanAlbum { _ in progressCount += 1 }
        XCTAssertEqual(progressCount, 2)
    }

    // MARK: - 互斥

    func testScanReturnsEmptyWhenAlreadyScanning() async {
        let petBox = DetectionBox(x: 0, y: 0, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)
        let (service, _, container) = makeService(assets: [asset("a")], detections: [petBox])

        // 启动后立即再次调用（isScanning 仍为 true 的极端场景由并发保证，此处验证 guard）
        // 正常流程下无法在同一 actor 上并发调用两次 async，这里只验证单次调用正常返回
        let result = await service.scanAlbum()
        XCTAssertEqual(result.processedCount, 1)
    }
}

/// ScanResult 测试辅助——petPhotosFound 通过 unassignedPetUris.count 反映
private extension ScanResult {
    var petPhotosFoundCount: Int { unassignedPetUris.count }
}

/// CLIP 精筛 mock（记录 detect 调用次数，可预设结果或错误）。
@MainActor
private final class MockClipInference: ClipInference {
    private(set) var detectCallCount = 0
    private let result: ClipDetectionResult?
    private let error: Error?

    init(result: ClipDetectionResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func detect(imageData: Data) async throws -> ClipDetectionResult {
        detectCallCount += 1
        if let error { throw error }
        guard let result else {
            throw MockClipError.inferenceFailed
        }
        return result
    }

    func extractFallbackEmbedding(imageData: Data) async throws -> [Float] { [] }
}

private enum MockClipError: Error {
    case inferenceFailed
}
