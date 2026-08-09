import XCTest
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MiLens

/// ImportService 测试——导入编排逻辑（对应源端 PhotoScanner.importPhotos）。
/// 使用 in-memory SwiftData + mock 平台服务，覆盖入库、去重、上限。
///
/// 注：container 必须由 makeService 返回并持有——mainContext 不持有 container，
/// 局部变量释放后 repo 的 fetch 会触发 SwiftData 内部 SIGTRAP（悬垂引用）。
@MainActor
final class ImportServiceTests: XCTestCase {

    private func makeService(
        assets: [PhotoAssetMetadata] = [],
        library: MockPhotoLibraryAccess? = nil
    ) -> (ImportService, SwiftDataPhotoRepository, MockFileStorage, ModelContainer) {
        // container 必须返回并持有——mainContext 不持有 container，
        // 局部变量释放后 repo 的 fetch 触发 SwiftData 内部 SIGTRAP（悬垂引用）。
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let photoLibrary = library ?? MockPhotoLibraryAccess(assets: assets)
        let fileStorage = MockFileStorage()
        let mediaLifecycle = MediaLifecycleService(
            photoRepo: photoRepo, petRepo: petRepo,
            fileStorage: fileStorage, sandboxDir: "/documents/MiPhotos")
        let service = ImportService(
            photoLibrary: photoLibrary, fileStorage: fileStorage,
            photoRepo: photoRepo, mediaLifecycle: mediaLifecycle,
            sandboxDir: "/documents/MiPhotos", petRepo: petRepo
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
        let result = await service.importPhotos(identifiers: ["a"])
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.matched, 0)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].originalURI, "a")
    }

    func testImportMultiplePhotos() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a"), asset("b"), asset("c")])
        let result = await service.importPhotos(identifiers: ["a", "b", "c"])
        XCTAssertEqual(result.imported, 3)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 3)
    }

    // MARK: - 去重（originalURI 为主键，P0 修复）

    func testImportSkipsAlreadyImportedIdentifiers() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a"), asset("b")])
        // 第一次导入
        _ = await service.importPhotos(identifiers: ["a", "b"])
        // 再次导入相同 identifier
        let result = await service.importPhotos(identifiers: ["a"])
        XCTAssertEqual(result.imported, 0)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 2) // 仍然是 2 张
    }

    func testImportSkipsByOriginalURIEvenIfSandboxPathDiffers() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a"), asset("b")])
        // 已入库照片：uri 是沙盒副本路径（UUID 文件名，与 identifier 无关），
        // originalURI = "a"——去重必须以 originalURI 为准。
        try! photoRepo.insertPhoto(Photo(uri: "/documents/MiPhotos/xyz.jpg", originalURI: "a"))

        // 再次导入 "a" → 按 originalURI 跳过；"b" 正常导入
        let result = await service.importPhotos(identifiers: ["a", "b"])
        XCTAssertEqual(result.imported, 1)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 2)
    }

    func testImportSkipsDuplicateIdentifiersWithinBatch() async {
        let (service, photoRepo, _, container) = makeService(assets: [asset("a"), asset("b")])
        // 同一批次内重复 identifier 只导入一次
        let result = await service.importPhotos(identifiers: ["a", "a", "b", "b", "a"])
        XCTAssertEqual(result.imported, 2)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 2)
    }

    // MARK: - 配额（ADR-0010）：重复 identifier 不误算为超额导入

    /// 免费用户已有 49 张，传入两次同一个新 ID（实际唯一 1 张）。
    /// 修复前：uniqueRequested=2（未去重输入），allowed=1，quotaBlocked=1（误拦）。
    /// 修复后：candidates=1（有序去重），allowed=1，quotaBlocked=0（正确）。
    func testDuplicateIdentifierDoesNotInflateQuotaBlock() async {
        let existingIDs = (0..<49).map { "existing_\($0)" }
        let assets = existingIDs.map { asset($0) } + [asset("new1")]
        let (service, photoRepo, _, container) = makeService(assets: assets)
        // 预导入 49 张（免费版上限 50）
        _ = await service.importPhotos(identifiers: existingIDs)

        // 传入同一个新 ID 两次 → 只导入 1 张，无配额拦截
        let result = await service.importPhotos(identifiers: ["new1", "new1"])
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.quotaBlocked, 0, "重复 identifier 不应误算为配额拦截")

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 100)
        XCTAssertEqual(photos.count, 50)
    }

    /// 60 张全新唯一照片，免费版配额 50 张仍有剩余（0 已有）。
    /// maxImportBatch=50 截断后 50 张在配额内 → quotaBlocked=0。
    /// 修复前：uniqueRequested=60，allowed=50，quotaBlocked=10（把截断误算为配额拦截）。
    func testBatchTruncationNotAttributedToQuota() async {
        let assets = (0..<60).map { asset("photo_\($0)") }
        let (service, photoRepo, _, container) = makeService(assets: assets)
        let identifiers = (0..<60).map { "photo_\($0)" }

        let result = await service.importPhotos(identifiers: identifiers)
        XCTAssertEqual(result.imported, ScanConfig.maxImportBatch)
        XCTAssertEqual(result.quotaBlocked, 0, "批次截断不应误算为配额拦截")
    }

    /// 免费用户已有 49 张，传入 3 张不同的新 ID → 导入 1 张，拦截 2 张。
    func testQuotaBlockedForGenuinelyOverLimit() async {
        let existingIDs = (0..<49).map { "existing_\($0)" }
        let assets = existingIDs.map { asset($0) }
            + [asset("new1"), asset("new2"), asset("new3")]
        let (service, photoRepo, _, container) = makeService(assets: assets)
        _ = await service.importPhotos(identifiers: existingIDs)

        let result = await service.importPhotos(identifiers: ["new1", "new2", "new3"])
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.quotaBlocked, 2, "真正超出配额的应被拦截")
    }

    // MARK: - 空输入

    func testImportEmptyIdentifiersReturnsZero() async {
        let (service, _, _, container) = makeService(assets: [])
        let result = await service.importPhotos(identifiers: [])
        XCTAssertEqual(result.imported, 0)
    }

    // MARK: - 上限

    func testImportRespectsMaxBatch() async {
        // 生成 60 个 asset（超过 maxImportBatch=50）
        let assets = (0..<60).map { asset("photo_\($0)") }
        let (service, photoRepo, _, container) = makeService(assets: assets)
        let identifiers = (0..<60).map { "photo_\($0)" }
        let result = await service.importPhotos(identifiers: identifiers)
        XCTAssertEqual(result.imported, ScanConfig.maxImportBatch)

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

    // MARK: - 自动归属（导入时匹配已注册宠物，对应源端 importPhotos 匹配链路）

    func testImportAutoMatchesRegisteredPet() async throws {
        // 1. 注册一只宠物（8 张橙色图 + 固定 clip embedding）
        let (_, petRepo, photoRepo, container) = makeAutoMatchService(
            assets: [asset("a")],
            imageDataOverrides: ["a": makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60)]
        )
        let pet = Pet(name: "小橘")
        try petRepo.insertPet(pet)
        let clip = MockClipInference()
        let matcher = PetMatcher(
            petRepo: petRepo, clipService: clip,
            executor: AnalysisExecutor(maxConcurrent: 1))
        let images = (0..<8).map { _ in makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60) }
        let registered = await matcher.registerPetFeatures(petID: pet.id, imageDatas: images)
        XCTAssertTrue(registered)

        // 2. 用同一 CLIP mock + 同色图片导入 → 自动归属到该宠物
        let service2 = ImportService(
            photoLibrary: MockPhotoLibraryAccess(
                assets: [asset("a")],
                imageDataOverrides: ["a": makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60)]
            ),
            fileStorage: MockFileStorage(),
            photoRepo: photoRepo, mediaLifecycle: MediaLifecycleService(
                photoRepo: photoRepo, petRepo: petRepo,
                fileStorage: MockFileStorage(), sandboxDir: "/documents/MiPhotos"),
            sandboxDir: "/documents/MiPhotos", petRepo: petRepo,
            clipService: clip
        )

        let result = await service2.importPhotos(identifiers: ["a"])
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.matched, 1)

        // 照片已归属 + 宠物照片计数已刷新
        let photos = try photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos[0].pet?.id, pet.id)
        XCTAssertEqual(try petRepo.getPet(id: pet.id)?.photoCount, 1)
    }

    func testImportAutoMatchSkipsWhenNoRegisteredPet() async throws {
        // 有 CLIP 模型但没有任何已注册宠物 → 导入正常，matched = 0
        let clip = MockClipInference()
        let (service, _, _, container) = makeAutoMatchService(
            assets: [asset("a")],
            imageDataOverrides: ["a": makeSolidPNG(width: 64, height: 64, r: 10, g: 200, b: 80)],
            clip: clip
        )

        let result = await service.importPhotos(identifiers: ["a"])
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.matched, 0)
    }

    func testImportAutoMatchFailsGracefullyOnExtractionError() async throws {
        // CLIP detect 失败 → 降级 fallback 提取（无注册宠物）→ 导入仍成功，matched = 0
        let failingClip = MockClipInference(detectError: ImportTestError.extractionFailed)
        let (service, _, _, container) = makeAutoMatchService(
            assets: [asset("a")],
            imageDataOverrides: ["a": makeSolidPNG(width: 64, height: 64, r: 200, g: 60, b: 60)],
            clip: failingClip
        )

        let result = await service.importPhotos(identifiers: ["a"])
        XCTAssertEqual(result.imported, 1, "特征提取失败不应阻止导入")
        XCTAssertEqual(result.matched, 0)
    }

    // MARK: - 失败可观测（H4）

    func testImportCountsPartialFailures() async {
        // a 加载失败、b 正常 → imported=1, failed=1（部分失败不阻止后续）
        let library = MockPhotoLibraryAccess(assets: [asset("a"), asset("b")])
        library.imageDataErrors = ["a": ImportTestError.loadFailed]
        let (service, photoRepo, _, container) = makeService(
            assets: [asset("a"), asset("b")], library: library)

        let result = await service.importPhotos(identifiers: ["a", "b"])
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.failed, 1)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].originalURI, "b")
    }

    func testImportCountsAllFailures() async {
        // 全部加载失败 → imported=0, failed=2（UI 应提示失败而非"没有新照片"）
        let library = MockPhotoLibraryAccess(assets: [asset("a"), asset("b")])
        library.imageDataErrors = ["a": ImportTestError.loadFailed, "b": ImportTestError.loadFailed]
        let (service, _, _, container) = makeService(
            assets: [asset("a"), asset("b")], library: library)

        let result = await service.importPhotos(identifiers: ["a", "b"])
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 2)
        XCTAssertEqual(ImportFlowLogic.resolveImportSummary(
            imported: result.imported, matched: result.matched, failed: result.failed),
            "有 2 张照片导入失败")
    }

    // MARK: - 自动归属辅助

    /// 构造带可选 CLIP mock 的导入服务（返回 petRepo 供注册特征）。
    private func makeAutoMatchService(
        assets: [PhotoAssetMetadata],
        imageDataOverrides: [String: Data] = [:],
        clip: (any ClipInference)? = nil
    ) -> (ImportService, SwiftDataPetRepository, SwiftDataPhotoRepository, ModelContainer) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let library = MockPhotoLibraryAccess(assets: assets, imageDataOverrides: imageDataOverrides)
        let fileStorage = MockFileStorage()
        let mediaLifecycle = MediaLifecycleService(
            photoRepo: photoRepo, petRepo: petRepo,
            fileStorage: fileStorage, sandboxDir: "/documents/MiPhotos")
        let service = ImportService(
            photoLibrary: library, fileStorage: fileStorage,
            photoRepo: photoRepo, mediaLifecycle: mediaLifecycle,
            sandboxDir: "/documents/MiPhotos", petRepo: petRepo,
            clipService: clip
        )
        return (service, petRepo, photoRepo, container)
    }

    /// 生成纯色 PNG 图片数据（供 decodeToRGBA 解码）。
    private func makeSolidPNG(width: Int, height: Int, r: Int, g: Int, b: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(
            red: CGFloat(r) / 255, green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

private enum ImportTestError: Error {
    case extractionFailed
    case loadFailed
}
