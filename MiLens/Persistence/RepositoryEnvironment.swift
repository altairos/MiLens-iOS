//  Repository 的 EnvironmentKey 注入（DESIGN.md §4.1 DI）。
//  应用级 Repository 在 MiLensApp.init 构造，通过 .environment 注入。
//  ViewModel 通过 @Environment 消费协议，不引用具体实现。
//  默认值 fatal：App 必须注入真实实现；不提供 in-memory 兜底以避免静默隐藏注入遗漏。

import SwiftUI

// MARK: - PetRepository

private struct PetRepositoryKey: EnvironmentKey {
    static var defaultValue: any PetRepositoryProtocol {
        fatalError("PetRepository 必须通过 .environment(\\.petRepository, ...) 注入")
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
    static var defaultValue: any PhotoRepositoryProtocol {
        fatalError("PhotoRepository 必须通过 .environment(\\.photoRepository, ...) 注入")
    }
}

extension EnvironmentValues {
    var photoRepository: any PhotoRepositoryProtocol {
        get { self[PhotoRepositoryKey.self] }
        set { self[PhotoRepositoryKey.self] = newValue }
    }
}
