//  Repository 的 EnvironmentKey 注入（DESIGN.md §4.1 DI）。
//  应用级 Repository 在 MiLensApp.init 构造，通过 .environment 注入。
//  ViewModel 通过 @Environment 消费协议，不引用具体实现。
//  默认值提供 in-memory 兜底：测试 host 启动 app 时未注入也不会崩溃；
//  正常运行时 App 在 body 第一时间注入真实实现覆盖默认值。

import SwiftUI
import SwiftData

// MARK: - fallback 共享容器

/// 环境 fallback 的共享 in-memory 容器。
/// 必须 static 缓存：mainContext 不持有 container，每次 defaultValue 新建容器
/// 会在返回后释放，repo 的 fetch 触发 SwiftData 内部 SIGTRAP（悬垂引用，已在测试中复现）。
/// internal：ViewModelFactory 的 Preview 默认值复用同一容器。
@MainActor
enum FallbackContainer {
    static let shared: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // EnvironmentKey.defaultValue 同步不可抛错，fallback 已是最后兜底；
            // 创建失败属于 SwiftData 基础设施异常，显式崩溃并携带 underlying error 以便诊断。
            fatalError("无法创建 fallback in-memory ModelContainer: \(error)")
        }
    }()
}

// MARK: - PetRepository

private struct PetRepositoryKey: EnvironmentKey {
    // EnvironmentKey.defaultValue 要求非隔离，而 fallback 容器为 @MainActor；
    // SwiftUI 只在主线程读取环境默认值（视图更新路径），assumeIsolated 显式固化
    // 该不变量——离主访问立即崩溃暴露，而非静默数据竞争。
    static var defaultValue: any PetRepositoryProtocol {
        MainActor.assumeIsolated {
            SwiftDataPetRepository(context: FallbackContainer.shared.mainContext)
        }
    }
}

extension EnvironmentValues {
    var petRepository: any PetRepositoryProtocol {
        get { self[PetRepositoryKey.self] }
        set { self[PetRepositoryKey.self] = newValue }
    }
}

// MARK: - PhotoRepository

private struct PhotoRepositoryKey: EnvironmentKey {
    // 同 PetRepositoryKey：非隔离要求 + 主线程读取不变量。
    static var defaultValue: any PhotoRepositoryProtocol {
        MainActor.assumeIsolated {
            SwiftDataPhotoRepository(context: FallbackContainer.shared.mainContext)
        }
    }
}

extension EnvironmentValues {
    var photoRepository: any PhotoRepositoryProtocol {
        get { self[PhotoRepositoryKey.self] }
        set { self[PhotoRepositoryKey.self] = newValue }
    }
}

// MARK: - ViewModelFactory（分层收敛：View 只依赖工厂，见 App/ViewModelFactory.swift）

private struct ViewModelFactoryKey: EnvironmentKey {
    /// 默认工厂（Preview/测试 host）：in-memory 容器 + mock 平台适配，
    /// 与 RepositoryEnvironment/PlatformEnvironment 的既有默认值语义一致。
    /// 同上：defaultValue 要求非隔离，经 assumeIsolated 固化主线程读取不变量。
    static var defaultValue: ViewModelFactory {
        MainActor.assumeIsolated {
            ViewModelFactory(
                container: FallbackContainer.shared,
                photoRepo: SwiftDataPhotoRepository(context: FallbackContainer.shared.mainContext),
                petRepo: SwiftDataPetRepository(context: FallbackContainer.shared.mainContext),
                photoLibrary: MockPhotoLibraryAccess(),
                vision: MockVisionService(),
                fileStorage: MockFileStorage(),
                clipService: nil,
                poseService: nil,
                cursorStore: UserDefaultsScanCursorStore(),
                mediaLifecycle: nil
            )
        }
    }
}

extension EnvironmentValues {
    var viewModelFactory: ViewModelFactory {
        get { self[ViewModelFactoryKey.self] }
        set { self[ViewModelFactoryKey.self] = newValue }
    }
}
