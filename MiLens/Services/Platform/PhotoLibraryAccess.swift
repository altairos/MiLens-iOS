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
    /// 系统库添加时间（对应源端 dateAdded，增量扫描过滤用）。
    /// iOS 无公开「加入相册时间」API，真实实现以 creationDate 近似填充（诚实标注）。
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

/// 保存到相册的资源类型（对应 PHAssetResourceType 的 photo/video 二分）。
enum PhotoLibrarySaveKind: Sendable, Equatable {
    case photo
    case video
}

/// 照片库访问协议。
/// 扫描/导入（读取）与创作导出（保存）共用；保存经 save(imageData:as:) 收敛
/// （P2-1 / ADR-0011 §2.2，消除 BeadExportService 直接 import Photos 的豁免）。
/// Sendable：实现类无共享可变状态（或单线程测试 mock），供后台执行器捕获。
protocol PhotoLibraryAccess: Sendable {
    /// 流式遍历系统相册照片元数据（对应源端 streamPhotoAssets）。
    /// - Parameter consumer: 每张照片的回调，返回 false 时提前终止（对应源端 stopSignal/consumer 返回值）。
    ///   回调支持 async——ScanService 需在回调内加载图片数据并调用 AI 检测。
    /// - Returns: 已遍历的资产数量。
    func streamPhotos(_ consumer: @escaping (PhotoAssetMetadata) async throws -> Bool) async throws -> Int

    /// 照片总数（对应源端 getPhotoAssetCount）。
    func photoCount() async throws -> Int

    /// 统计系统图库中 creationDate >= date 的照片数量（新照片提醒用，毫秒级计数不解码）。
    /// date 为 nil 时返回全库 count（首次无游标场景兜底）。
    /// 诚实标注：iOS 无公开「加入系统图库时间」API，以 creationDate 近似。
    func countPhotosAddedSince(_ date: Date?) async throws -> Int

    /// 按 identifier 查询单张照片元数据，不存在返回 nil（对应源端 getAssetByUri）。
    func metadata(forIdentifier identifier: String) async throws -> PhotoAssetMetadata?

    /// 加载照片的图片数据（对应源端 ImageUtils.loadPixelMap）。
    /// - Parameters:
    ///   - identifier: PHAsset localIdentifier
    ///   - maxDimension: 最大边长（像素）。0 = 原始尺寸（导入用），>0 = 缩放（AI 检测用）。
    /// - Returns: 编码后的图片数据（JPEG/PNG），供 VisionService/CoreML 解码。
    func loadImageData(forIdentifier identifier: String, maxDimension: Int) async throws -> Data

    // ── 保存（创作导出共用：拼豆图纸/红包封面/宠物卡片等，P2-1 收敛）──

    /// 保存图片数据到系统相册（对应源端 createAsset + writePixelMapAsPng）。
    /// 需要 NSPhotoLibraryAddUsageDescription（已配置）。
    /// - Throws: `PhotoLibraryError.savePermissionDenied`（addOnly 授权被拒/受限）、
    ///   `PhotoLibraryError.saveFailed`（performChanges 底层失败）。
    func save(imageData: Data, as kind: PhotoLibrarySaveKind) async throws

    // ── 授权（对应源端 PermissionHelper，Onboarding 权限步骤用）──

    /// 当前授权状态。
    func authorizationStatus() async -> PhotoLibraryAuthorizationStatus

    /// 请求授权（系统弹窗）。
    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus
}

// MARK: - Mock（对应源端 FakeMediaAccess）

/// 预设照片列表的 mock，用于单元测试。
final class MockPhotoLibraryAccess: PhotoLibraryAccess, @unchecked Sendable {
    private let assets: [PhotoAssetMetadata]
    /// 预设的图片数据（按 identifier 查找；未预设时返回占位 Data）
    private let imageDataOverrides: [String: Data]
    /// 可配置的授权状态（默认 authorized，保持既有测试不破坏）
    var authorizationStatusValue: PhotoLibraryAuthorizationStatus = .authorized
    /// requestAuthorization 调用后生效的状态（默认与当前状态一致）
    var requestedResult: PhotoLibraryAuthorizationStatus? = nil
    /// 失败注入：photoCount() 抛错（扫描失败路径测试用）
    var photoCountError: Error?
    /// 失败注入：streamPhotos() 遍历前抛错（扫描中断路径测试用）
    var streamError: Error?
    /// 失败注入：metadata(forIdentifier:) 抛错（导入失败清理路径测试用）
    var metadataError: Error?
    /// 失败注入：loadImageData(forIdentifier:) 按 identifier 抛错（H4 导入失败计数测试用）
    var imageDataErrors: [String: Error] = [:]
    /// 可注入的新照片计数（默认按 assets 的 dateAdded/creationDate 过滤；
    /// 测试可直接赋值固定结果，简化 ViewModel 测试）。
    var newPhotoCountOverride: Int? = nil
    /// 失败注入：save(imageData:as:) 抛错（保存失败/权限拒绝路径测试用）
    var saveError: Error?
    /// 已记录的 save 调用（数据 + 类型），供测试断言透传
    private(set) var saveCalls: [(data: Data, kind: PhotoLibrarySaveKind)] = []

    init(assets: [PhotoAssetMetadata] = [], imageDataOverrides: [String: Data] = [:]) {
        self.assets = assets
        self.imageDataOverrides = imageDataOverrides
    }

    func streamPhotos(_ consumer: @escaping (PhotoAssetMetadata) async throws -> Bool) async throws -> Int {
        if let streamError { throw streamError }
        var visited = 0
        for asset in assets {
            visited += 1
            if !(try await consumer(asset)) { break }
        }
        return visited
    }

    func photoCount() async throws -> Int {
        if let photoCountError { throw photoCountError }
        return assets.count
    }

    func countPhotosAddedSince(_ date: Date?) async throws -> Int {
        if let newPhotoCountOverride { return newPhotoCountOverride }
        if let date {
            return assets.filter { ($0.dateAdded ?? $0.dateTaken) ?? .distantPast >= date }.count
        }
        return assets.count
    }

    func metadata(forIdentifier identifier: String) async throws -> PhotoAssetMetadata? {
        if let metadataError { throw metadataError }
        return assets.first { $0.identifier == identifier }
    }

    func loadImageData(forIdentifier identifier: String, maxDimension: Int) async throws -> Data {
        if let error = imageDataErrors[identifier] { throw error }
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

    func save(imageData: Data, as kind: PhotoLibrarySaveKind) async throws {
        if let saveError { throw saveError }
        saveCalls.append((imageData, kind))
    }
}
