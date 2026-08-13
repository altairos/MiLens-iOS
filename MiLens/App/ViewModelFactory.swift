//  ViewModelFactory —— 页面 ViewModel 组合工厂（DESIGN.md §4.1 DI + 分层收敛）。
//
//  背景：此前页面各自通过 @Environment 直接持有 Repository/Service 拼装 ViewModel，
//  造成「View → Repository」分层漂移（View 需要知道 sandboxDir 拼装、in-memory 兜底等
//  基础设施细节）。统一改为：View 只依赖本工厂（随组合根注入），工厂负责组装。
//
//  边界：
//  - 工厂是组合根的一部分（AppDependencies 构造），不持有业务状态；
//  - 轻量页面（纯读照片列表/单张照片）的数据查询也经工厂，不再直连 Repository；
//  - 编辑器等依赖重服务的构造保留「环境缺失时 in-memory 兜底」语义（Preview/异常路径）。

import Foundation
import MiLensKit
import SwiftData

/// 页面 ViewModel 组合工厂（@MainActor——构造出的 VM 与 Repository 均为 MainActor 隔离）。
@MainActor
final class ViewModelFactory {

    private let container: ModelContainer
    private let photoRepo: any PhotoRepositoryProtocol
    private let petRepo: any PetRepositoryProtocol
    private let photoLibrary: any PhotoLibraryAccess
    private let vision: any VisionService
    private let fileStorage: any FileStorage
    private let clipService: (any ClipInference)?
    private let poseService: (any PoseInference)?
    private let cursorStore: any ScanCursorStore
    private let mediaLifecycle: MediaLifecycleService?

    init(container: ModelContainer,
         photoRepo: any PhotoRepositoryProtocol,
         petRepo: any PetRepositoryProtocol,
         photoLibrary: any PhotoLibraryAccess,
         vision: any VisionService,
         fileStorage: any FileStorage,
         clipService: (any ClipInference)?,
         poseService: (any PoseInference)?,
         cursorStore: any ScanCursorStore,
         mediaLifecycle: MediaLifecycleService?) {
        self.container = container
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.photoLibrary = photoLibrary
        self.vision = vision
        self.fileStorage = fileStorage
        self.clipService = clipService
        self.poseService = poseService
        self.cursorStore = cursorStore
        self.mediaLifecycle = mediaLifecycle
    }

    /// 媒体沙盒目录（Documents/MiPhotos，DESIGN.md §7 唯一入库路径）。
    /// 由工厂统一拼装——此前 GalleryView/EditorView 各自重复计算。
    var sandboxDir: String {
        URL.documentsDirectory
            .appendingPathComponent(ScanConfig.sandboxDirName)
            .path
    }

    /// 编辑产物目录（Documents/MiPhotos/Edits）——编辑成品允许备份，
    /// 与排除备份的导入副本分区（DESIGN.md §7）。
    var editsDir: String {
        sandboxDir + "/" + ScanConfig.editsDirName
    }

    // MARK: - ViewModel 构造

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            photoRepository: photoRepo,
            petRepository: petRepo,
            photoLibrary: photoLibrary,
            scanCursorStore: cursorStore
        )
    }

    /// 回忆提醒中心 ViewModel（首页铃铛入口，复用 photoRepo/petRepo）。
    func makeMemoryRemindersViewModel() -> MemoryRemindersViewModel {
        MemoryRemindersViewModel(photoRepository: photoRepo, petRepository: petRepo)
    }

    func makeGalleryViewModel() -> GalleryViewModel {
        GalleryViewModel(
            photoRepo: photoRepo,
            petRepo: petRepo,
            photoLibrary: photoLibrary,
            vision: vision,
            fileStorage: fileStorage,
            sandboxDir: sandboxDir,
            clipService: clipService,
            cursorStore: cursorStore,
            mediaLifecycle: mediaLifecycle
        )
    }

    func makePetEditViewModel() -> PetEditViewModel {
        PetEditViewModel(petRepo: petRepo, clipService: clipService)
    }

    /// 拼豆工作室 ViewModel（评审收敛：View 不再直连 photoRepo/vision/clip/pose 服务）。
    func makeBeadViewModel(isPro: Bool) -> BeadViewModel {
        BeadViewModel(
            photoRepo: photoRepo,
            vision: vision,
            clipService: clipService,
            poseService: poseService,
            isPro: isPro
        )
    }

    /// 宠物档案列表 ViewModel（评审收敛：View 不再直连 petRepo）。
    func makePetProfileViewModel(isPro: Bool) -> PetProfileViewModel {
        PetProfileViewModel(petRepo: petRepo, isPro: isPro)
    }

    /// 成长时间线 ViewModel（评审收敛：View 不再直连 petRepo/photoRepo）。
    func makeTimelineViewModel() -> TimelineViewModel {
        TimelineViewModel(petRepo: petRepo, photoRepo: photoRepo)
    }

    /// 编辑器 ViewModel：环境缺失（Preview/异常路径）时用 in-memory 容器兜底；
    /// 兜底也失败则返回 nil，调用方保持黑屏而不崩溃（语义与原 EditorView.fallbackLifecycle 一致）。
    func makeEditorViewModel(photoID: UUID) -> EditorViewModel? {
        let lifecycle = mediaLifecycle ?? Self.makeFallbackLifecycle(
            container: container,
            photoRepo: photoRepo,
            fileStorage: fileStorage
        )
        guard let lifecycle else { return nil }
        return EditorViewModel(
            photoID: photoID,
            photoRepo: photoRepo,
            visionService: vision,
            imageProcessor: CoreImageEditorProcessing(),
            saveService: EditorSaveService(
                mediaLifecycle: lifecycle,
                sandboxDir: sandboxDir,
                editsDir: editsDir
            ),
            // 装饰资源目录从 Bundle 加载（V1.0 默认空；素材面板上线后填充）。
            decorationCatalog: DecorationCatalogLoader.load()
        )
    }

    // MARK: - 轻量数据查询（无 ViewModel 页面的唯一数据入口）

    func photoList(limit: Int) throws -> [Photo] {
        try photoRepo.getPhotosPage(offset: 0, limit: limit)
    }

    func photo(id: UUID) throws -> Photo? {
        try photoRepo.getPhoto(id: id)
    }

    func pet(id: UUID) throws -> Pet? {
        try petRepo.getPet(id: id)
    }

    func photosByPet(_ pet: Pet) throws -> [Photo] {
        try photoRepo.getPhotosByPet(pet)
    }

    func unassignedPhotos(limit: Int) throws -> [Photo] {
        try photoRepo.getUnassignedPhotos(limit: limit)
    }

    /// 全部宠物（时间线筛选等轻量列表的唯一数据入口）。
    func allPets() throws -> [Pet] {
        try petRepo.getAllPets()
    }

    // MARK: - 红包工作室

    /// 红包草稿目录（Documents/RedPacketDrafts）。
    var redPacketDraftsDir: URL {
        URL.documentsDirectory.appendingPathComponent("RedPacketDrafts", isDirectory: true)
    }

    /// 红包工作室 ViewModel。
    func makeRedPacketWorkshopViewModel(
        templateID: String, photoID: UUID, petID: UUID?, isPro: Bool
    ) -> RedPacketWorkshopViewModel {
        RedPacketWorkshopViewModel(
            templateID: templateID,
            photoID: photoID,
            petID: petID,
            isPro: isPro,
            photoRepo: photoRepo,
            vision: vision,
            draftStore: RedPacketDraftStore(draftsDir: redPacketDraftsDir),
            imageQualityAnalyzer: CoreGraphicsRedPacketImageQualityAnalyzer()
        )
    }

    // MARK: - 候选缩略图（AlbumScanFlow 候选页）

    /// 加载系统相册候选照片的缩略图（256px JPEG Data → UIImage）。
    /// 候选尚未导入沙盒，直接从系统相册按 identifier 加载低分辨率数据。
    func loadCandidateThumbnail(identifier: String) async -> UIImage? {
        guard let data = try? await photoLibrary.loadImageData(
            forIdentifier: identifier, maxDimension: 256
        ) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - 写操作（手动归属/移出）

    /// 将一组照片归属到指定宠物（nil = 移出归属），同步刷新受影响宠物的 photoCount 缓存。
    /// 是用户手动纠正 AI 自动归属的唯一入口（对应 P0 手动归属 UI）。
    /// - Parameters:
    ///   - photos: 待归属的照片列表
    ///   - pet: 目标宠物（nil = 移出归属，不归属任何宠物）
    /// - Returns: 受影响（已刷新 photoCount）的宠物列表
    @discardableResult
    func assignPhotos(_ photos: [Photo], to pet: Pet?) throws -> [Pet] {
        try PhotoAssignmentLogic.assign(
            photos: photos, to: pet,
            photoRepo: photoRepo, petRepo: petRepo)
    }

    // MARK: - 编辑器兜底（环境未注入 MediaLifecycleService 时）

    private static func makeFallbackLifecycle(
        container: ModelContainer,
        photoRepo: any PhotoRepositoryProtocol,
        fileStorage: any FileStorage
    ) -> MediaLifecycleService? {
        return MediaLifecycleService(
            photoRepo: photoRepo,
            petRepo: SwiftDataPetRepository(context: container.mainContext),
            fileStorage: fileStorage,
            sandboxDir: URL.documentsDirectory
                .appendingPathComponent(ScanConfig.sandboxDirName)
                .path
        )
    }
}

// MARK: - EnvironmentKey 注入（定义见 RepositoryEnvironment.swift，与其余 EnvironmentKey 同文件）
