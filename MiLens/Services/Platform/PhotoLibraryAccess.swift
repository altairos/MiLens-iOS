//  PhotoLibraryAccess —— 系统照片库访问协议（对应源端 IMediaAccess）。
//  把 Photos 框架的直接调用隔离在此协议后面，
//  使 ScanService / ImportService 可以通过 mock 覆盖扫描与导入路径。
//  DESIGN.md §9 平台适配层。

import Foundation

/// 从系统照片库提取的纯数据结构（对应源端 PhotoAssetData，不含系统 API 依赖）。
struct PhotoAssetMetadata: Equatable, Sendable {
    /// PHAsset localIdentifier（对应源端 uri，唯一标识系统库中的照片）
    let identifier: String
    let dateTaken: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int64
    let displayName: String
}

/// 照片库访问协议。
/// V1.0 仅含扫描所需方法；保存到相册（createAsset）待 P4 创作导出时追加。
protocol PhotoLibraryAccess {
    /// 流式遍历系统相册照片元数据（对应源端 streamPhotoAssets）。
    /// - Parameter consumer: 每张照片的回调，返回 false 时提前终止（对应源端 stopSignal/consumer 返回值）。
    /// - Returns: 已遍历的资产数量。
    func streamPhotos(_ consumer: @escaping (PhotoAssetMetadata) -> Bool) async throws -> Int

    /// 照片总数（对应源端 getPhotoAssetCount）。
    func photoCount() async throws -> Int

    /// 按 identifier 查询单张照片元数据，不存在返回 nil（对应源端 getAssetByUri）。
    func metadata(forIdentifier identifier: String) async throws -> PhotoAssetMetadata?
}

// MARK: - Mock（对应源端 FakeMediaAccess）

/// 预设照片列表的 mock，用于单元测试。
final class MockPhotoLibraryAccess: PhotoLibraryAccess {
    private let assets: [PhotoAssetMetadata]

    init(assets: [PhotoAssetMetadata] = []) {
        self.assets = assets
    }

    func streamPhotos(_ consumer: @escaping (PhotoAssetMetadata) -> Bool) async throws -> Int {
        var visited = 0
        for asset in assets {
            visited += 1
            if !consumer(asset) { break }
        }
        return visited
    }

    func photoCount() async throws -> Int {
        assets.count
    }

    func metadata(forIdentifier identifier: String) async throws -> PhotoAssetMetadata? {
        assets.first { $0.identifier == identifier }
    }
}
