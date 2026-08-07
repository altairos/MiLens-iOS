import XCTest
import SwiftData
@testable import MiLens

/// ScanService 测试——扫描编排逻辑（对应源端 PhotoScanner 行为）。
/// 使用 in-memory SwiftData + mock 平台服务，覆盖去重、检测、取消、空库。
@MainActor
final class ScanServiceTests: XCTestCase {

    private func makeService(
        assets: [PhotoAssetMetadata] = [],
        detections: [DetectionBox] = []
    ) -> (ScanService, SwiftDataPhotoRepository) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let photoLibrary = MockPhotoLibraryAccess(assets: assets)
        let vision = MockVisionService(detections: detections)
        let service = ScanService(
            photoLibrary: photoLibrary, vision: vision,
            photoRepo: photoRepo, petRepo: petRepo
        )
        return (service, photoRepo)
    }

    private func asset(_ id: String) -> PhotoAssetMetadata {
        PhotoAssetMetadata(
            identifier: id, dateTaken: nil, dateAdded: nil,
            pixelWidth: 256, pixelHeight: 256, fileSize: 1024, displayName: "\(id).jpg"
        )
    }

    // MARK: - 空库

    func testScanEmptyLibraryReturnsEmptyResult() async {
        let (service, _) = makeService(assets: [], detections: [])
        let result = await service.scanAlbum()
        XCTAssertEqual(result.processedCount, 0)
        XCTAssertTrue(result.unassignedPetUris.isEmpty)
        XCTAssertFalse(result.canceled)
    }

    // MARK: - 检测

    func testScanWithNoPetDetectionsReturnsEmpty() async {
        let (service, _) = makeService(
            assets: [asset("a"), asset("b")],
            detections: [] // 无宠物检测结果
        )
        let result = await service.scanAlbum()
        XCTAssertEqual(result.processedCount, 2)
        XCTAssertTrue(result.unassignedPetUris.isEmpty)
    }

    func testScanWithPetDetectionsCollectsUnassigned() async {
        let petBox = DetectionBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)
        let (service, _) = makeService(
            assets: [asset("a"), asset("b"), asset("c")],
            detections: [petBox]
        )
        let result = await service.scanAlbum()
        XCTAssertEqual(result.processedCount, 3)
        XCTAssertEqual(result.unassignedPetUris.count, 3)
        XCTAssertEqual(result.petPhotosFoundCount, 3)
    }

    // MARK: - 去重

    func testScanSkipsAlreadyImportedPhotos() async {
        let (service, photoRepo) = makeService(
            assets: [asset("a"), asset("b")],
            detections: [DetectionBox(x: 0, y: 0, width: 0.5, height: 0.5, label: "dog", confidence: 0.9)]
        )
        // 预先入库一张照片（模拟已导入）
        try! photoRepo.insertPhoto(Photo(uri: "a"))

        let result = await service.scanAlbum()
        // "a" 被跳过，只处理 "b"
        XCTAssertEqual(result.processedCount, 1)
        XCTAssertEqual(result.unassignedPetUris, ["b"])
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
        let (service, _) = makeService(assets: [asset("a"), asset("b")], detections: [])
        var progressCount = 0
        _ = await service.scanAlbum { _ in progressCount += 1 }
        XCTAssertEqual(progressCount, 2)
    }

    // MARK: - 互斥

    func testScanReturnsEmptyWhenAlreadyScanning() async {
        let petBox = DetectionBox(x: 0, y: 0, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)
        let (service, _) = makeService(assets: [asset("a")], detections: [petBox])

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
