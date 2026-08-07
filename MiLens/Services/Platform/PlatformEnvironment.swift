//  平台适配层的 EnvironmentKey 注入（DESIGN.md §4.1 DI + §9 平台隔离）。
//  应用级适配器在 MiLensApp 构造，通过 .environment 注入。
//  ViewModel / Service 通过 @Environment 消费协议，不引用具体实现。
//  默认值提供 mock 兜底（测试 host 启动时不崩溃）；
//  真实实现待 P1.5 AI 路线定案后在 MiLensApp.init 注入。

import SwiftUI

// MARK: - PhotoLibraryAccess

private struct PhotoLibraryAccessKey: EnvironmentKey {
    static var defaultValue: any PhotoLibraryAccess {
        MockPhotoLibraryAccess()
    }
}

extension EnvironmentValues {
    var photoLibraryAccess: any PhotoLibraryAccess {
        get { self[PhotoLibraryAccessKey.self] }
        set { self[PhotoLibraryAccessKey.self] = newValue }
    }
}

// MARK: - FileStorage

private struct FileStorageKey: EnvironmentKey {
    static var defaultValue: any FileStorage {
        MockFileStorage()
    }
}

extension EnvironmentValues {
    var fileStorage: any FileStorage {
        get { self[FileStorageKey.self] }
        set { self[FileStorageKey.self] = newValue }
    }
}

// MARK: - VisionService

private struct VisionServiceKey: EnvironmentKey {
    static var defaultValue: any VisionService {
        MockVisionService()
    }
}

extension EnvironmentValues {
    var visionService: any VisionService {
        get { self[VisionServiceKey.self] }
        set { self[VisionServiceKey.self] = newValue }
    }
}

// MARK: - InferenceEngine

private struct InferenceEngineKey: EnvironmentKey {
    static var defaultValue: (any InferenceEngine)? {
        nil
    }
}

extension EnvironmentValues {
    var inferenceEngine: (any InferenceEngine)? {
        get { self[InferenceEngineKey.self] }
        set { self[InferenceEngineKey.self] = newValue }
    }
}
