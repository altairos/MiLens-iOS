import XCTest
import SwiftData
@testable import MiLens

/// ImportService 测试——导入编排逻辑（对应源端 PhotoScanner.importPhotos）。
/// 使用 in-memory SwiftData + mock 平台服务，覆盖入库、去重、上限。
@MainActor
final class ImportServiceTests: XCTestCase {

    private func makeService(
        assets: [PhotoAssetMetadata] = []
    ) -> (ImportService, SwiftDataPhotoRepository, MockFileStorage) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let photoLibrary = MockPhotoLibraryAccess(assets: assets)
        let fileStorage = MockFileStorage()
        let service = ImportService(
            photoLibrary: photoLibrary, fileStorage: fileStorage,
            photoRepo: photoRepo, sandboxDir: "/documents/MiPhotos"
        )
        return (service, photoRepo, fileStorage)
    }

    private func asset(_ id: String) -> PhotoAssetMetadata {
        PhotoAssetMetadata(
            identifier: id, dateTaken: Date(timeIntervalSince1970: 1000), dateAdded: nil,
            pixelWidth: 1080, pixelHeight: 1920, fileSize: 2048, displayName: "\(id).jpg"
        )
    }

    // MARK: - 基本导入

    func testImportCreatesPhotoRecord() async {
        let (service, photoRepo, _) = makeService(assets: [asset("a")])
        let count = await service.importPhotos(identifiers: ["a"])
        XCTAssertEqual(count, 1)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].originalURI, "a")
    }

    func testImportMultiplePhotos() async {
        let (service, photoRepo, _) = makeService(assets: [asset("a"), asset("b"), asset("c")])
        let count = await service.importPhotos(identifiers: ["a", "b", "c"])
        XCTAssertEqual(count, 3)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 3)
    }

    // MARK: - 去重

    func testImportSkipsAlreadyImportedIdentifiers() async {
        let (service, photoRepo, _) = makeService(assets: [asset("a"), asset("b")])
        // 第一次导入
        _ = await service.importPhotos(identifiers: ["a", "b"])
        // 再次导入相同 identifier
        let count = await service.importPhotos(identifiers: ["a"])
        XCTAssertEqual(count, 0)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 2) // 仍然是 2 张
    }

    // MARK: - 空输入

    func testImportEmptyIdentifiersReturnsZero() async {
        let (service, _, _) = makeService(assets: [])
        let count = await service.importPhotos(identifiers: [])
        XCTAssertEqual(count, 0)
    }

    // MARK: - 上限

    func testImportRespectsMaxBatch() async {
        // 生成 60 个 asset（超过 maxImportBatch=50）
        let assets = (0..<60).map { asset("photo_\($0)") }
        let (service, photoRepo, _) = makeService(assets: assets)
        let identifiers = (0..<60).map { "photo_\($0)" }
        let count = await service.importPhotos(identifiers: identifiers)
        XCTAssertEqual(count, ScanConfig.maxImportBatch)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 100)
        XCTAssertEqual(photos.count, ScanConfig.maxImportBatch)
    }

    // MARK: - 元数据

    func testImportPreservesDimensions() async {
        let (service, photoRepo, _) = makeService(assets: [asset("a")])
        _ = await service.importPhotos(identifiers: ["a"])
        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos[0].width, 1080)
        XCTAssertEqual(photos[0].height, 1920)
    }

    func testImportSetsPetPhotoCategory() async {
        let (service, photoRepo, _) = makeService(assets: [asset("a")])
        _ = await service.importPhotos(identifiers: ["a"])
        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos[0].category, "pet_photo")
    }

    // MARK: - 进度回调

    func testImportReportsProgress() async {
        let (service, _, _) = makeService(assets: [asset("a"), asset("b")])
        var reported: [Int] = []
        _ = await service.importPhotos(identifiers: ["a", "b"]) { progress in
            reported.append(progress.current)
        }
        XCTAssertEqual(reported, [1, 2])
    }
}
