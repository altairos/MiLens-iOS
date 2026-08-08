//  AppDependencies —— 应用依赖容器（组合根，DESIGN.md §4.1）。
//  MiLensApp 的依赖构造抽成可重试工厂：ModelContainer 创建失败时进入
//  DatabaseRecoveryView，用户可重试或重建本地数据（销毁持久化存储后重新构造）。
//
//  依赖分组：
//  - 持久层：ModelContainer + SwiftData 仓储（失败唯一可恢复入口在启动路径）
//  - 平台适配层：VisionService / ClipInference / PhotoLibraryAccess / FileStorage
//  - 服务层：MediaLifecycleService（事务一致性）/ NotifyService（纪念提醒调度）

import Foundation
import SwiftData

@MainActor
final class AppDependencies {

    let container: ModelContainer
    let petRepo: any PetRepositoryProtocol
    let photoRepo: any PhotoRepositoryProtocol
    let vision: any VisionService
    let clipService: ClipInferenceService?
    let photoLibrary: any PhotoLibraryAccess
    let fileStorage: any FileStorage
    let scanCursorStore: any ScanCursorStore
    let mediaLifecycle: MediaLifecycleService
    let notifyService: NotifyService?
    let onboardingViewModel: OnboardingViewModel
    let storeService: any StoreService

    init(container: ModelContainer,
         petRepo: any PetRepositoryProtocol,
         photoRepo: any PhotoRepositoryProtocol,
         vision: any VisionService,
         clipService: ClipInferenceService?,
         photoLibrary: any PhotoLibraryAccess,
         fileStorage: any FileStorage,
         scanCursorStore: any ScanCursorStore,
         mediaLifecycle: MediaLifecycleService,
         notifyService: NotifyService?,
         onboardingViewModel: OnboardingViewModel,
         storeService: any StoreService) {
        self.container = container
        self.petRepo = petRepo
        self.photoRepo = photoRepo
        self.vision = vision
        self.clipService = clipService
        self.photoLibrary = photoLibrary
        self.fileStorage = fileStorage
        self.scanCursorStore = scanCursorStore
        self.mediaLifecycle = mediaLifecycle
        self.notifyService = notifyService
        self.onboardingViewModel = onboardingViewModel
        self.storeService = storeService
    }

    /// 构造完整依赖图。失败时抛出——调用方进入可诊断恢复界面。
    /// - Parameter isTesting: 测试环境切 in-memory 容器（避免模拟器 Application
    ///   Support 目录不可写导致 CoreData 存储错误噪音）。
    static func make(isTesting: Bool) throws -> AppDependencies {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = isTesting
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration()
        let container = try ModelContainer(
            for: schema,
            migrationPlan: MiLensMigrationPlan.self,
            configurations: [config]
        )

        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        // 平台适配层：注入真实 VisionService（VNClassifyImageRequest 宠物预筛 + VNGenerateForegroundInstanceMask 分割）。
        // ClipInferenceService 在测试环境跳过（避免加载 ~80MB CLIP 模型拖慢单测）。
        let vision: any VisionService = IOSVisionService()
        let clipService = isTesting ? nil : ClipInferenceService.create()
        // 照片库适配器：真实 Photos 框架实现（授权 + 流式遍历）。
        let photoLibrary: any PhotoLibraryAccess = IOSPhotoLibraryAccess()
        // 文件存储：真实 FileManager 实现（导入/编辑产物写入沙盒，重启后仍存在）。
        let fileStorage: any FileStorage = IOSFileStorage()
        // 媒体生命周期：事务一致性（导入回滚 / 删除联动 / 启动孤儿审计）。
        let sandboxDir = URL.documentsDirectory
            .appendingPathComponent(ScanConfig.sandboxDirName).path
        let mediaLifecycle = MediaLifecycleService(
            photoRepo: photoRepo,
            petRepo: petRepo,
            fileStorage: fileStorage,
            sandboxDir: sandboxDir
        )
        // 扫描游标：UserDefaults 持久化上次成功扫描时刻（增量扫描过滤基准）。
        let scanCursorStore = UserDefaultsScanCursorStore()
        // 纪念提醒：真调度（宠物纪念日 + 时光机）。测试环境不构造，避免触发通知授权。
        let notifyService = isTesting ? nil : NotifyService(
            photoRepo: photoRepo,
            petRepo: petRepo,
            poster: IOSNotificationCenter()
        )
        // 首次启动引导状态机（onFinish 置位持久化标记，触发 @AppStorage 切换主界面）。
        let onboardingViewModel = OnboardingViewModel(
            photoRepo: photoRepo,
            petRepo: petRepo,
            photoLibrary: photoLibrary,
            vision: vision,
            onFinish: {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            },
            clipService: clipService,
            cursorStore: scanCursorStore
        )
        // 订阅服务：StoreKit 2 真实实现（测试环境用 mock，避免启动 Transaction.updates 监听）。
        let storeService: any StoreService = isTesting ? MockStoreService() : StoreKit2StoreService()

        return AppDependencies(
            container: container,
            petRepo: petRepo,
            photoRepo: photoRepo,
            vision: vision,
            clipService: clipService,
            photoLibrary: photoLibrary,
            fileStorage: fileStorage,
            scanCursorStore: scanCursorStore,
            mediaLifecycle: mediaLifecycle,
            notifyService: notifyService,
            onboardingViewModel: onboardingViewModel,
            storeService: storeService
        )
    }

    /// 重建本地数据：销毁默认持久化存储（含 -wal/-shm 伴生文件）。
    /// 仅清除 MiLens 本地记录；系统相册原图不受影响。
    /// 注意：重建后重新启动会执行孤儿审计，Documents/MiPhotos 下无 DB 记录的照片副本
    /// （导入/编辑产物）会被一并删除——恢复界面文案已明确提示（DatabaseRecoveryView）。
    static func destroyPersistentStore() throws {
        let storeURL = ModelConfiguration().url
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let fileURL = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: fileURL.path) {
                try fm.removeItem(at: fileURL)
            }
        }
    }
}
