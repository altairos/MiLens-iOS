//  平台适配层的 EnvironmentKey 注入（DESIGN.md §4.1 DI + §9 平台隔离）。
//  应用级适配器在 MiLensApp 构造，通过 .environment 注入。
//  ViewModel / Service 通过 @Environment 消费协议，不引用具体实现。
//  默认值提供 mock/in-memory 兜底（测试 host 启动时不崩溃）；
//  生产环境由 MiLensApp.init 注入真实实现（IOSFileStorage / UserDefaultsScanCursorStore 等）。

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

// MARK: - ScanCursorStore（上次成功扫描游标，增量扫描过滤基准）

private struct ScanCursorStoreKey: EnvironmentKey {
    static var defaultValue: any ScanCursorStore {
        UserDefaultsScanCursorStore()
    }
}

extension EnvironmentValues {
    var scanCursorStore: any ScanCursorStore {
        get { self[ScanCursorStoreKey.self] }
        set { self[ScanCursorStoreKey.self] = newValue }
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

// MARK: - ClipInferenceService（CLIP 推理编排，模型缺失时为 nil）

private struct ClipInferenceServiceKey: EnvironmentKey {
    static var defaultValue: ClipInferenceService? { nil }
}

extension EnvironmentValues {
    var clipInferenceService: ClipInferenceService? {
        get { self[ClipInferenceServiceKey.self] }
        set { self[ClipInferenceServiceKey.self] = newValue }
    }
}

// MARK: - NotifyService（纪念提醒每日检查，测试环境不注入为 nil）

private struct NotifyServiceKey: EnvironmentKey {
    @MainActor
    static var defaultValue: NotifyService? { nil }
}

extension EnvironmentValues {
    var notifyService: NotifyService? {
        get { self[NotifyServiceKey.self] }
        set { self[NotifyServiceKey.self] = newValue }
    }
}
