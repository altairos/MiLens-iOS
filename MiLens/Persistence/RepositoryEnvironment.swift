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
        let schema = Schema(versionedSchema: SchemaV1.self)
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
    @MainActor
    static var defaultValue: any PetRepositoryProtocol {
        SwiftDataPetRepository(context: FallbackContainer.shared.mainContext)
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
    @MainActor
    static var defaultValue: any PhotoRepositoryProtocol {
        SwiftDataPhotoRepository(context: FallbackContainer.shared.mainContext)
    }
}

extension EnvironmentValues {
    var photoRepository: any PhotoRepositoryProtocol {
        get { self[PhotoRepositoryKey.self] }
        set { self[PhotoRepositoryKey.self] = newValue }
    }
}
