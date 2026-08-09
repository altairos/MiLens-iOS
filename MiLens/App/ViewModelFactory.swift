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
    private let cursorStore: any ScanCursorStore
    private let mediaLifecycle: MediaLifecycleService?

    init(container: ModelContainer,
         photoRepo: any PhotoRepositoryProtocol,
         petRepo: any PetRepositoryProtocol,
         photoLibrary: any PhotoLibraryAccess,
         vision: any VisionService,
         fileStorage: any FileStorage,
         clipService: (any ClipInference)?,
         cursorStore: any ScanCursorStore,
         mediaLifecycle: MediaLifecycleService?) {
        self.container = container
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.photoLibrary = photoLibrary
        self.vision = vision
        self.fileStorage = fileStorage
        self.clipService = clipService
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

    // MARK: - ViewModel 构造

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(photoRepository: photoRepo, petRepository: petRepo)
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
                sandboxDir: sandboxDir
            )
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

// MARK: - EnvironmentKey 注入

private struct ViewModelFactoryKey: EnvironmentKey {
    /// 默认工厂（Preview/测试 host）：in-memory 容器 + mock 平台适配，
    /// 与 RepositoryEnvironment/PlatformEnvironment 的既有默认值语义一致。
    @MainActor
    static var defaultValue: ViewModelFactory {
        ViewModelFactory(
            container: FallbackContainer.shared,
            photoRepo: SwiftDataPhotoRepository(context: FallbackContainer.shared.mainContext),
            petRepo: SwiftDataPetRepository(context: FallbackContainer.shared.mainContext),
            photoLibrary: MockPhotoLibraryAccess(),
            vision: MockVisionService(),
            fileStorage: MockFileStorage(),
            clipService: nil,
            cursorStore: UserDefaultsScanCursorStore(),
            mediaLifecycle: nil
        )
    }
}

extension EnvironmentValues {
    var viewModelFactory: ViewModelFactory {
        get { self[ViewModelFactoryKey.self] }
        set { self[ViewModelFactoryKey.self] = newValue }
    }
}
