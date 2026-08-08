//  PhotoLibraryAccess —— 系统照片库访问协议（对应源端 IMediaAccess）。
//  把 Photos 框架的直接调用隔离在此协议后面，
//  使 ScanService / ImportService / Onboarding 可以通过 mock 覆盖扫描与导入路径。
//  DESIGN.md §9 平台适配层。

import Foundation

/// 照片库授权状态（对应源端 PermissionHelper 的权限状态枚举）。
enum PhotoLibraryAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    /// 仅限选中的照片（iOS 14+ PHAuthorizationStatus.limited）
    case limited
    case authorized
}

/// 从系统照片库提取的纯数据结构（对应源端 PhotoAssetData，不含系统 API 依赖）。
struct PhotoAssetMetadata: Equatable, Sendable {
    /// PHAsset localIdentifier（对应源端 uri，唯一标识系统库中的照片）
    let identifier: String
    /// EXIF 拍摄时间（对应源端 dateTaken，可能为 nil）
    let dateTaken: Date?
    /// 系统库添加时间（对应源端 dateAdded，扫描新增照片模式过滤用）
    let dateAdded: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int64
    let displayName: String

    /// 测试用便利构造（dateAdded 默认 nil，保持已有测试简洁）
    init(identifier: String, dateTaken: Date?, dateAdded: Date? = nil,
         pixelWidth: Int, pixelHeight: Int, fileSize: Int64, displayName: String) {
        self.identifier = identifier
        self.dateTaken = dateTaken
        self.dateAdded = dateAdded
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
        self.displayName = displayName
    }
}

/// 照片库访问协议。
/// V1.0 仅含扫描所需方法；保存到相册（createAsset）待 P4 创作导出时追加。
protocol PhotoLibraryAccess {
    /// 流式遍历系统相册照片元数据（对应源端 streamPhotoAssets）。
    /// - Parameter consumer: 每张照片的回调，返回 false 时提前终止（对应源端 stopSignal/consumer 返回值）。
    ///   回调支持 async——ScanService 需在回调内加载图片数据并调用 AI 检测。
    /// - Returns: 已遍历的资产数量。
    func streamPhotos(_ consumer: @escaping (PhotoAssetMetadata) async throws -> Bool) async throws -> Int

    /// 照片总数（对应源端 getPhotoAssetCount）。
    func photoCount() async throws -> Int

    /// 按 identifier 查询单张照片元数据，不存在返回 nil（对应源端 getAssetByUri）。
    func metadata(forIdentifier identifier: String) async throws -> PhotoAssetMetadata?

    /// 加载照片的图片数据（对应源端 ImageUtils.loadPixelMap）。
    /// - Parameters:
    ///   - identifier: PHAsset localIdentifier
    ///   - maxDimension: 最大边长（像素）。0 = 原始尺寸（导入用），>0 = 缩放（AI 检测用）。
    /// - Returns: 编码后的图片数据（JPEG/PNG），供 VisionService/CoreML 解码。
    func loadImageData(forIdentifier identifier: String, maxDimension: Int) async throws -> Data

    // ── 授权（对应源端 PermissionHelper，Onboarding 权限步骤用）──

    /// 当前授权状态。
    func authorizationStatus() async -> PhotoLibraryAuthorizationStatus

    /// 请求授权（系统弹窗）。
    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus
}

// MARK: - Mock（对应源端 FakeMediaAccess）

/// 预设照片列表的 mock，用于单元测试。
final class MockPhotoLibraryAccess: PhotoLibraryAccess {
    private let assets: [PhotoAssetMetadata]
    /// 预设的图片数据（按 identifier 查找；未预设时返回占位 Data）
    private let imageDataOverrides: [String: Data]
    /// 可配置的授权状态（默认 authorized，保持既有测试不破坏）
    var authorizationStatusValue: PhotoLibraryAuthorizationStatus = .authorized
    /// requestAuthorization 调用后生效的状态（默认与当前状态一致）
    var requestedResult: PhotoLibraryAuthorizationStatus? = nil

    init(assets: [PhotoAssetMetadata] = [], imageDataOverrides: [String: Data] = [:]) {
        self.assets = assets
        self.imageDataOverrides = imageDataOverrides
    }

    func streamPhotos(_ consumer: @escaping (PhotoAssetMetadata) async throws -> Bool) async throws -> Int {
        var visited = 0
        for asset in assets {
            visited += 1
            if !(try await consumer(asset)) { break }
        }
        return visited
    }

    func photoCount() async throws -> Int {
        assets.count
    }

    func metadata(forIdentifier identifier: String) async throws -> PhotoAssetMetadata? {
        assets.first { $0.identifier == identifier }
    }

    func loadImageData(forIdentifier identifier: String, maxDimension: Int) async throws -> Data {
        if let data = imageDataOverrides[identifier] { return data }
        // 未预设时返回非空占位数据，使检测管线可运行
        return Data([0xFF, 0xD8, 0xFF]) // JPEG SOI 标记
    }

    func authorizationStatus() async -> PhotoLibraryAuthorizationStatus {
        authorizationStatusValue
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        if let requestedResult { return requestedResult }
        return authorizationStatusValue
    }
}
