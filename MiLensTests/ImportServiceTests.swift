import XCTest
import SwiftData
@testable import MiLens

/// ImportService 测试——导入编排逻辑（对应源端 PhotoScanner.importPhotos）。
/// 使用 in-memory SwiftData + mock 平台服务，覆盖入库、去重、上限。
///
/// 注：container 必须由 makeService 返回并持有——mainContext 不持有 container，
/// 局部变量释放后 repo 的 fetch 会触发 SwiftData 内部 SIGTRAP（悬垂引用）。
@MainActor
final class ImportServiceTests: XCTestCase {

    private func makeService(
        assets: [PhotoAssetMetadata] = []
    ) -> (ImportService, SwiftDataPhotoRepository, MockFileStorage, ModelContainer) {
        // container 必须返回并持有——mainContext 不持有 container，
        // 局部变量释放后 repo 的 fetch 触发 SwiftData 内部 SIGTRAP（悬垂引用）。
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let photoLibrary = MockPhotoLibraryAccess(assets: assets)
        let fileStorage = MockFileStorage()
        let mediaLifecycle = MediaLifecycleService(
            photoRepo: photoRepo, petRepo: petRepo,
            fileStorage: fileStorage, sandboxDir: "/documents/MiPhotos")
        let service = ImportService(
            photoLibrary: photoLibrary, fileStorage: fileStorage,
            photoRepo: photoRepo, mediaLifecycle: mediaLifecycle,
            sandboxDir: "/documents/MiPhotos"
        )
        return (service, photoRepo, fileStorage, container)
    }

    private func asset(_ id: String) -> PhotoAssetMetadata {
        PhotoAssetMetadata(
            identifier: id, dateTaken: Date(timeIntervalSince1970: 1000), dateAdded: nil,
            pixelWidth: 1080, pixelHeight: 1920, fileSize: 2048, displayName: "\(id).jpg"
        )
    }

    // MARK: - 基本导入

    func testImportCreatesPhotoRecord() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a")])
        let count = await service.importPhotos(identifiers: ["a"])
        XCTAssertEqual(count, 1)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].originalURI, "a")
    }

    func testImportMultiplePhotos() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a"), asset("b"), asset("c")])
        let count = await service.importPhotos(identifiers: ["a", "b", "c"])
        XCTAssertEqual(count, 3)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 3)
    }

    // MARK: - 去重（originalURI 为主键，P0 修复）

    func testImportSkipsAlreadyImportedIdentifiers() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a"), asset("b")])
        // 第一次导入
        _ = await service.importPhotos(identifiers: ["a", "b"])
        // 再次导入相同 identifier
        let count = await service.importPhotos(identifiers: ["a"])
        XCTAssertEqual(count, 0)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 2) // 仍然是 2 张
    }

    func testImportSkipsByOriginalURIEvenIfSandboxPathDiffers() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a"), asset("b")])
        // 已入库照片：uri 是沙盒副本路径（UUID 文件名，与 identifier 无关），
        // originalURI = "a"——去重必须以 originalURI 为准。
        try! photoRepo.insertPhoto(Photo(uri: "/documents/MiPhotos/xyz.jpg", originalURI: "a"))

        // 再次导入 "a" → 按 originalURI 跳过；"b" 正常导入
        let count = await service.importPhotos(identifiers: ["a", "b"])
        XCTAssertEqual(count, 1)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 2)
    }

    func testImportSkipsDuplicateIdentifiersWithinBatch() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a"), asset("b")])
        // 同一批次内重复 identifier 只导入一次
        let count = await service.importPhotos(identifiers: ["a", "a", "b", "b", "a"])
        XCTAssertEqual(count, 2)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 2)
    }

    // MARK: - 空输入

    func testImportEmptyIdentifiersReturnsZero() async {
        let (service, _, _, container) = makeService(assets: [])
        let count = await service.importPhotos(identifiers: [])
        XCTAssertEqual(count, 0)
    }

    // MARK: - 上限

    func testImportRespectsMaxBatch() async {
        // 生成 60 个 asset（超过 maxImportBatch=50）
        let assets = (0..<60).map { asset("photo_\($0)") }
        let (service, photoRepo, _, container) = makeService(assets: assets)
        let identifiers = (0..<60).map { "photo_\($0)" }
        let count = await service.importPhotos(identifiers: identifiers)
        XCTAssertEqual(count, ScanConfig.maxImportBatch)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 100)
        XCTAssertEqual(photos.count, ScanConfig.maxImportBatch)
    }

    // MARK: - 元数据

    func testImportPreservesDimensions() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a")])
        _ = await service.importPhotos(identifiers: ["a"])
        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos[0].width, 1080)
        XCTAssertEqual(photos[0].height, 1920)
    }

    func testImportSetsPetPhotoCategory() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a")])
        _ = await service.importPhotos(identifiers: ["a"])
        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos[0].category, "pet_photo")
    }

    // MARK: - 进度回调

    func testImportReportsProgress() async {
        let (service, _, _, container) = makeService(assets: [asset("a"), asset("b")])
        var reported: [Int] = []
        _ = await service.importPhotos(identifiers: ["a", "b"]) { progress in
            reported.append(progress.current)
        }
        XCTAssertEqual(reported, [1, 2])
    }

    // MARK: - 文件名（UUID，避免短哈希碰撞覆盖已有文件）

    func testImportUsesUUIDFileNameMatchingPhotoID() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a")])
        _ = await service.importPhotos(identifiers: ["a"])

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1)
        // 沙盒文件名 = UUID（大写）且与 Photo.id 的 uuidString 一致
        let fileName = URL(fileURLWithPath: photos[0].uri).lastPathComponent
        XCTAssertEqual(fileName, photos[0].id.uuidString + ".jpg")
        XCTAssertNotEqual(fileName, "a.jpg") // 不再是 identifier 的短哈希
    }
}
