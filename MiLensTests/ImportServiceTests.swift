import XCTest
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MiLens

/// ImportService 测试——导入编排逻辑（对应源端 PhotoScanner.importPhotos）。
/// 使用 in-memory SwiftData + mock 平台服务，覆盖入库、去重、上限。
///
/// 注：container 由 makeService 内部 keepAlive 保活——mainContext 不持有 container，
/// 释放后 repo 的 fetch 会触发 SwiftData 内部 SIGTRAP（悬垂引用）。
@MainActor
final class ImportServiceTests: XCTestCase {

    /// 保活所有 in-memory container 至测试类结束（对齐 PhotoRepositoryTests 模式），
    /// 防止用例解构丢弃 container 后 fetch 崩溃。
    private var keepAlive: [ModelContainer] = []

    private func makeService(
        assets: [PhotoAssetMetadata] = [],
        library: MockPhotoLibraryAccess? = nil
    ) -> (ImportService, SwiftDataPhotoRepository, MockFileStorage, ModelContainer) {
        // container 保活进 keepAlive——mainContext 不持有 container，
        // 释放后 repo 的 fetch 触发 SwiftData 内部 SIGTRAP（悬垂引用）。
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        keepAlive.append(container)
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

    // MARK: - importedPhotoIDs（P1 修复：返回实际导入照片 ID）

    func testImportResultContainsActualPhotoIDs() async {
        let (service, photoRepo, _, _) = makeService(assets: [asset("a"), asset("b"), asset("c")])
        let result = await service.importPhotos(identifiers: ["a", "b", "c"])
        XCTAssertEqual(result.importedPhotoIDs.count, 3, "importedPhotoIDs 须与导入数量一致")

        // 每个返回的 ID 都能在 DB 中查到对应的 Photo 记录
        for photoID in result.importedPhotoIDs {
            let photo = try! photoRepo.getPhoto(id: photoID)
            XCTAssertNotNil(photo, "importedPhotoIDs 中的 ID 须对应实际入库记录")
        }
    }

    func testImportResultPhotoIDsMatchDBRecords() async {
        let (service, photoRepo, _, _) = makeService(assets: [asset("a"), asset("b")])
        let result = await service.importPhotos(identifiers: ["a", "b"])

        let dbPhotos = Set(try! photoRepo.getPhotosPage(offset: 0, limit: 10).map(\.id))
        XCTAssertEqual(Set(result.importedPhotoIDs), dbPhotos,
                       "importedPhotoIDs 须与 DB 中的照片 ID 完全一致")
    }

    func testImportResultPhotoIDsEmptyOnNoImport() async {
        let (service, _, _, _) = makeService(assets: [])
        let result = await service.importPhotos(identifiers: [])
        XCTAssertTrue(result.importedPhotoIDs.isEmpty, "空导入时 importedPhotoIDs 须为空")
    }

    func testImportResultPhotoIDsExcludesFailed() async {
        // a 加载失败、b 正常 → importedPhotoIDs 只含 b 的 ID
        let library = MockPhotoLibraryAccess(assets: [asset("a"), asset("b")])
        library.imageDataErrors = ["a": ImportTestError.loadFailed]
        let (service, photoRepo, _, _) = makeService(assets: [asset("a"), asset("b")], library: library)

        let result = await service.importPhotos(identifiers: ["a", "b"])
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.importedPhotoIDs.count, 1, "失败照片的 ID 不应出现在 importedPhotoIDs")

        let photo = try! photoRepo.getPhoto(id: result.importedPhotoIDs[0])
        XCTAssertEqual(photo?.originalURI, "b")
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

    // MARK: - 自动归属批量原子性（P2 修复：多张匹配同一宠物计数一致）

    func testImportAutoMatchBatchAssignsMultiplePhotosConsistentCount() async throws {
        // 三张同特征照片匹配到同一宠物——批量归属（batchAssignPhotos）后
        // photoCount 须与实际关系一致，避免逐张 assignPhoto + refreshPhotoCount
        // 部分失败导致计数漂移。
        let clip = MockClipInference()
        let (_, petRepo, photoRepo, container) = makeAutoMatchService(
            assets: [asset("a"), asset("b"), asset("c")],
            imageDataOverrides: [
                "a": makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60),
                "b": makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60),
                "c": makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60),
            ],
            clip: clip
        )
        let pet = Pet(name: "小橘")
        try petRepo.insertPet(pet)
        let matcher = PetMatcher(
            petRepo: petRepo, clipService: clip,
            executor: AnalysisExecutor(maxConcurrent: 1))
        let images = (0..<8).map { _ in makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60) }
        // XCTest 断言的 autoclosure 不支持 async：先求值再断言。
        let registered = await matcher.registerPetFeatures(petID: pet.id, imageDatas: images)
        XCTAssertTrue(registered)

        let service2 = ImportService(
            photoLibrary: MockPhotoLibraryAccess(
                assets: [asset("a"), asset("b"), asset("c")],
                imageDataOverrides: [
                    "a": makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60),
                    "b": makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60),
                    "c": makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60),
                ]),
            fileStorage: MockFileStorage(),
            photoRepo: photoRepo, mediaLifecycle: MediaLifecycleService(
                photoRepo: photoRepo, petRepo: petRepo,
                fileStorage: MockFileStorage(), sandboxDir: "/documents/MiPhotos"),
            sandboxDir: "/documents/MiPhotos", petRepo: petRepo,
            clipService: clip
        )

        let result = await service2.importPhotos(identifiers: ["a", "b", "c"])
        XCTAssertEqual(result.imported, 3)
        XCTAssertEqual(result.matched, 3, "三张同特征照片应全部匹配到同一宠物")
        // 批量归属后 photoCount 须与实际归属照片数一致（验证 batchAssignPhotos 原子写入）
        XCTAssertEqual(try petRepo.getPet(id: pet.id)?.photoCount, 3,
                       "批量归属后计数须一致，不得逐张漂移")
        let photos = try photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 3)
        for photo in photos {
            XCTAssertEqual(photo.pet?.id, pet.id, "所有照片须归属到目标宠物")
        }
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

    // MARK: - 环境级失败与降级（建目录/去重读取/批量入库）

    /// 沙盒目录创建失败是环境级错误：直接终止本次导入（不计单张失败、不入库）。
    func testImportReturnsZeroWhenSandboxDirectoryCreationFails() async {
        let (service, photoRepo, fs, _) = makeService(assets: [asset("a")])
        fs.failCreateDirectory = true

        let result = await service.importPhotos(identifiers: ["a"])
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 0, "目录创建失败是环境级错误，不计为单张失败")
        XCTAssertEqual(result.quotaBlocked, 0)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertTrue(photos.isEmpty, "目录创建失败时不得有任何入库")
    }

    /// 读取既有 originalURI 失败 -> 降级空 Set 继续导入（去重失效但不中断导入流程）。
    /// 注：内存去重失效后，与既有记录重复的 URI 仍会被 DB 的 unique 约束兜底拒绝
    /// （双层防御），故用全新 ID 验证「降级不中断」语义本身。
    func testImportContinuesWithoutDedupWhenExistingURIsFetchFails() async throws {
        let (service, photoRepo, _) = makeFailingRepoService(failGetAllOriginalURIs: true)
        // DB 已有 originalURI = "a" 的记录（正常应被去重跳过）
        try photoRepo.insertPhoto(Photo(uri: "/documents/MiPhotos/xyz.jpg", originalURI: "a"))

        // 导入全新 ID：读取既有 URI 失败只影响去重，不应中断导入流程
        let result = await service.importPhotos(identifiers: ["b"])
        XCTAssertEqual(result.imported, 1, "读取既有 URI 失败时降级为不去重，导入不中断")
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.quotaBlocked, 0)

        // 预设记录 + 新导入各 1 条（重复 URI 的 DB unique 兜底由 flush 用例覆盖）
        let photos = try photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 2)
    }

    /// 批量入库失败（insertPhotos 抛错）-> 计数回本批数量，回滚已写沙盒文件。
    func testFlushFailureRollsBackFilesAndCountsBatchAsFailed() async throws {
        let (service, photoRepo, fs) = makeFailingRepoService(failInsertPhotos: true)

        let result = await service.importPhotos(identifiers: ["a", "b"])
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.failed, 2, "整批入库失败计数回本批数量")
        XCTAssertTrue(result.importedPhotoIDs.isEmpty)

        // 回滚验证：DB 无记录、已写沙盒副本被清理（不留孤儿文件）
        let photos = try photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertTrue(photos.isEmpty)
        XCTAssertTrue(fs.listFiles(in: "/documents/MiPhotos").isEmpty,
                      "批量入库失败须回滚删除本批已写文件")
    }

    // MARK: - 重入守卫 / 取消 / 配额进度 / Pro 切换

    /// 导入进行中的二次调用被重入守卫拦截：立即返回全 0，不影响首个调用。
    func testImportRejectsConcurrentInvocationWhileImporting() async {
        let gate = ImportGateLibrary(assets: [asset("a")])
        let (service, _, _) = makeServiceWithLibrary(gate)

        let first = Task { await service.importPhotos(identifiers: ["a"]) }
        // 等首个调用推进到 loadImageData（此刻 isImporting 已置位）
        await gate.waitForFirstLoad()

        let second = await service.importPhotos(identifiers: ["a"])
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.failed, 0)
        XCTAssertEqual(second.quotaBlocked, 0)
        XCTAssertFalse(second.cancelled)

        gate.release()
        let firstResult = await first.value
        XCTAssertEqual(firstResult.imported, 1, "首个调用不受重入守卫影响")
    }

    /// 处理中取消：循环 break 后尾批 flush——已处理照片照常入库（不留孤儿文件）。
    func testImportCancellationFlushesPendingPhotos() async {
        let gate = ImportGateLibrary(assets: [asset("a"), asset("b")])
        let (service, photoRepo, _) = makeServiceWithLibrary(gate)

        let task = Task { await service.importPhotos(identifiers: ["a", "b"]) }
        await gate.waitForFirstLoad()
        task.cancel()
        gate.release()

        let result = await task.value
        XCTAssertTrue(result.cancelled, "取消后结果须标记 cancelled 供 UI 区分提示")
        XCTAssertEqual(result.imported, 1, "取消前已处理的照片经尾批 flush 入库")
        XCTAssertEqual(result.failed, 0)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1)
    }

    /// 配额耗尽的照片不再入库，但进度回调仍逐张推进（调用方进度条不滞留）。
    func testQuotaExhaustedPhotosStillReportProgress() async {
        let existingIDs = (0..<49).map { i in "existing_\(i)" }
        let assets = existingIDs.map { id in asset(id) }
            + [asset("new1"), asset("new2"), asset("new3")]
        let (service, _, _, _) = makeService(assets: assets)
        _ = await service.importPhotos(identifiers: existingIDs)

        var reported: [Int] = []
        let result = await service.importPhotos(
            identifiers: ["new1", "new2", "new3"]) { progress in
                reported.append(progress.current)
            }
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.quotaBlocked, 2)
        XCTAssertEqual(reported, [1, 2, 3],
                       "被配额拦截的照片仍须推进进度（配额 continue 分支不跳过进度回调）")
    }

    /// 购买 Pro 后 updateProStatus 动态解除配额限制（无需重建服务）。
    func testUpdateProStatusLiftsQuotaLimit() async {
        let existingIDs = (0..<49).map { i in "existing_\(i)" }
        let assets = existingIDs.map { id in asset(id) }
            + [asset("new1"), asset("new2"), asset("new3")]
        let (service, photoRepo, _, _) = makeService(assets: assets)
        _ = await service.importPhotos(identifiers: existingIDs)

        service.updateProStatus(true)
        let result = await service.importPhotos(identifiers: ["new1", "new2", "new3"])
        XCTAssertEqual(result.imported, 3, "Pro 用户不受 50 张免费配额限制")
        XCTAssertEqual(result.quotaBlocked, 0)

        let photos = try! photoRepo.getPhotosPage(offset: 0, limit: 100)
        XCTAssertEqual(photos.count, 52)
    }

    // MARK: - 环境级失败辅助

    /// 构造使用失败注入仓储的导入服务（container 保活同 makeService）。
    private func makeFailingRepoService(
        failGetAllOriginalURIs: Bool = false,
        failInsertPhotos: Bool = false
    ) -> (ImportService, SwiftDataPhotoRepository, MockFileStorage) {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        keepAlive.append(container)
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let failing = ImportFailurePhotoRepository(base: photoRepo)
        failing.failGetAllOriginalURIs = failGetAllOriginalURIs
        failing.failInsertPhotos = failInsertPhotos
        let fileStorage = MockFileStorage()
        let service = ImportService(
            photoLibrary: MockPhotoLibraryAccess(assets: [asset("a"), asset("b")]),
            fileStorage: fileStorage,
            photoRepo: failing,
            mediaLifecycle: MediaLifecycleService(
                photoRepo: failing, petRepo: petRepo,
                fileStorage: fileStorage, sandboxDir: "/documents/MiPhotos"),
            sandboxDir: "/documents/MiPhotos", petRepo: petRepo)
        return (service, photoRepo, fileStorage)
    }

    /// 构造使用外部照片库实现的导入服务（重入/取消时序测试用）。
    private func makeServiceWithLibrary(
        _ library: any PhotoLibraryAccess
    ) -> (ImportService, SwiftDataPhotoRepository, MockFileStorage) {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        keepAlive.append(container)
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let fileStorage = MockFileStorage()
        let service = ImportService(
            photoLibrary: library, fileStorage: fileStorage,
            photoRepo: photoRepo,
            mediaLifecycle: MediaLifecycleService(
                photoRepo: photoRepo, petRepo: petRepo,
                fileStorage: fileStorage, sandboxDir: "/documents/MiPhotos"),
            sandboxDir: "/documents/MiPhotos", petRepo: petRepo)
        return (service, photoRepo, fileStorage)
    }
    // MARK: - 自动归属辅助

    /// 构造带可选 CLIP mock 的导入服务（返回 petRepo 供注册特征）。
    private func makeAutoMatchService(
        assets: [PhotoAssetMetadata],
        imageDataOverrides: [String: Data] = [:],
        clip: (any ClipInference)? = nil
    ) -> (ImportService, SwiftDataPetRepository, SwiftDataPhotoRepository, ModelContainer) {
        let schema = Schema(versionedSchema: SchemaV2.self)
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

/// 可控挂起的照片库 mock：首次 loadImageData 挂起直至 release（重入/取消时序测试用）。
/// loadCount 仅在 MainActor 串行导入循环中递增，无并发竞争。
private final class ImportGateLibrary: PhotoLibraryAccess, @unchecked Sendable {
    private let assets: [PhotoAssetMetadata]
    private var loadCount = 0
    private let firstLoadSignal = AsyncStream<Void>.makeStream()
    private let releaseGate = AsyncStream<Void>.makeStream()

    init(assets: [PhotoAssetMetadata]) {
        self.assets = assets
    }

    /// 等待首个 loadImageData 进入挂起（此刻调用方 importPhotos 已置 isImporting）。
    func waitForFirstLoad() async {
        for await _ in firstLoadSignal.stream { break }
    }

    /// 放行首次挂起的 loadImageData。
    func release() {
        releaseGate.continuation.yield()
    }

    func loadImageData(forIdentifier identifier: String, maxDimension: Int) async throws -> Data {
        loadCount += 1
        if loadCount == 1 {
            firstLoadSignal.continuation.yield()
            for await _ in releaseGate.stream { break }
        }
        return Data([0xFF, 0xD8, 0xFF])
    }

    func streamPhotos(_ consumer: @escaping (PhotoAssetMetadata) async throws -> Bool) async throws -> Int {
        var visited = 0
        for asset in assets {
            visited += 1
            if !(try await consumer(asset)) { break }
        }
        return visited
    }

    func photoCount() async throws -> Int { assets.count }

    func countPhotosAddedSince(_ date: Date?) async throws -> Int {
        if let date {
            return assets.filter { a in (a.dateAdded ?? a.dateTaken) ?? .distantPast >= date }.count
        }
        return assets.count
    }

    func metadata(forIdentifier identifier: String) async throws -> PhotoAssetMetadata? {
        assets.first { a in a.identifier == identifier }
    }

    func save(imageData: Data, as kind: PhotoLibrarySaveKind) async throws {}

    func authorizationStatus() async -> PhotoLibraryAuthorizationStatus { .authorized }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus { .authorized }
}

/// 仓储失败注入 wrapper（导入编排错误分支测试用）：
/// 默认全量转发 base，开关打开后对应方法抛 PhotoRepositoryFailure。
@MainActor
private final class ImportFailurePhotoRepository: PhotoRepositoryProtocol {
    private let base: SwiftDataPhotoRepository
    /// getAllOriginalURIs 抛错（导入去重读取失败降级路径）。
    var failGetAllOriginalURIs = false
    /// insertPhotos 抛错（导入批量入库失败回滚路径）。
    var failInsertPhotos = false

    init(base: SwiftDataPhotoRepository) {
        self.base = base
    }

    func getAllOriginalURIs() throws -> Set<String> {
        guard !failGetAllOriginalURIs else { throw PhotoRepositoryFailure() }
        return try base.getAllOriginalURIs()
    }

    func insertPhotos(_ photos: [Photo]) throws {
        guard !failInsertPhotos else { throw PhotoRepositoryFailure() }
        try base.insertPhotos(photos)
    }

    // -- 其余全量转发 --
    func getPhoto(id: UUID) throws -> Photo? { try base.getPhoto(id: id) }
    func getPhotoByURI(_ uri: String) throws -> Photo? { try base.getPhotoByURI(uri) }
    func getPhotoByOriginalURI(_ originalURI: String) throws -> Photo? {
        try base.getPhotoByOriginalURI(originalURI)
    }
    func getAllPhotoURIs() throws -> Set<String> { try base.getAllPhotoURIs() }
    func countAllPhotos() throws -> Int { try base.countAllPhotos() }
    func getLatestPhotoDate() throws -> Date? { try base.getLatestPhotoDate() }
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] {
        try base.getPhotosPage(offset: offset, limit: limit)
    }
    func getPhotosByPet(_ pet: Pet) throws -> [Photo] { try base.getPhotosByPet(pet) }
    func getUnassignedPhotos(limit: Int) throws -> [Photo] {
        try base.getUnassignedPhotos(limit: limit)
    }
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo] {
        try base.getAnniversaryPhotos(month: month, day: day, excludeYear: excludeYear)
    }
    func insertPhoto(_ photo: Photo) throws { try base.insertPhoto(photo) }
    func deletePhoto(_ photo: Photo) throws { try base.deletePhoto(photo) }
    func updatePhoto(_ photo: Photo) throws { try base.updatePhoto(photo) }
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws { try base.assignPhoto(photo, to: pet) }
    func batchAssignPhotos(_ photos: [Photo], to targetPet: Pet?) throws -> [Pet] {
        try base.batchAssignPhotos(photos, to: targetPet)
    }
    func setFavorite(_ photo: Photo, favorite: Bool) throws {
        try base.setFavorite(photo, favorite: favorite)
    }
    func updateNote(_ photo: Photo, note: String) throws {
        try base.updateNote(photo, note: note)
    }
    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo] {
        try base.getPendingQualityScorePhotos(limit: limit)
    }
    func getDuplicateCandidates() throws -> [Photo] { try base.getDuplicateCandidates() }
    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws {
        try base.updateQualityData(photo, sharpness: sharpness, qualityScore: qualityScore, phash: phash)
    }
    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws {
        try base.replaceDuplicateMarks(groups)
    }
}
