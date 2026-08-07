//  Repository 的 EnvironmentKey 注入（DESIGN.md §4.1 DI）。
//  应用级 Repository 在 MiLensApp.init 构造，通过 .environment 注入。
//  ViewModel 通过 @Environment 消费协议，不引用具体实现。
//  默认值提供 in-memory 兜底：测试 host 启动 app 时未注入也不会崩溃；
//  正常运行时 App 在 body 第一时间注入真实实现覆盖默认值。

import SwiftUI
import SwiftData

// MARK: - PetRepository

private struct PetRepositoryKey: EnvironmentKey {
    @MainActor
    static var defaultValue: any PetRepositoryProtocol {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return SwiftDataPetRepository(context: container.mainContext)
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
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return SwiftDataPhotoRepository(context: container.mainContext)
    }
}

extension EnvironmentValues {
    var photoRepository: any PhotoRepositoryProtocol {
        get { self[PhotoRepositoryKey.self] }
        set { self[PhotoRepositoryKey.self] = newValue }
    }
}
