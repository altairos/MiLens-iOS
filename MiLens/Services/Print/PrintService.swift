//  PrintService —— 实体打印增值服务接口预留（ADR-0010 §7）。
//
//  未来推出配套实体产品（照片相册、明信片、拼豆成品、文创周边等），
//  用户在 App 内下单定制。V1 仅预留接口，不实现后端对接。
//
//  架构原则：业务层依赖 PrintService 协议，不依赖具体实现。
//  V1 提供 UnavailablePrintService 占位实现，UI 检测到不可用时隐藏入口。
//  后续接入真实后端只需替换实现。

import Foundation

// MARK: - 产品类型

/// 实体打印产品类型（ADR-0010 §7.2）。
public enum PrintProductType: String, CaseIterable, Identifiable, Codable, Sendable {
    /// 宠物相册（精装印刷，从照片库选择）。
    case photoAlbum
    /// 明信片套装（基于宠物卡片模板印刷）。
    case postcardSet
    /// 拼豆成品/套装（按拼豆图纸配珠）。
    case beadKit
    /// 文创周边（手机壳、帆布画、马克杯等）。
    case merchandise

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .photoAlbum:    return "宠物相册"
        case .postcardSet:   return "明信片套装"
        case .beadKit:       return "拼豆成品"
        case .merchandise:   return "文创周边"
        }
    }

    public var systemImage: String {
        switch self {
        case .photoAlbum:    return "book.closed"
        case .postcardSet:   return "envelope"
        case .beadKit:       return "shippingbox"
        case .merchandise:   return "cup.and.saucer"
        }
    }
}

// MARK: - 数据模型

/// 打印产品规格（尺寸/材质/数量等选项）。
public struct PrintProductSpec: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let type: PrintProductType
    public let name: String
    public let description: String
    /// 可选规格（如「A4 精装 / A5 软皮」「16 张 / 32 张」）。
    public let options: [PrintSpecOption]
    /// 预览图资源名（Asset Catalog 或系统图标）。
    public let previewImageName: String

    public init(
        id: String, type: PrintProductType, name: String,
        description: String, options: [PrintSpecOption], previewImageName: String
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.description = description
        self.options = options
        self.previewImageName = previewImageName
    }
}

/// 规格选项（如尺寸、数量、材质）。
public struct PrintSpecOption: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String       // 如「A4 精装」
    public let priceAddition: Int  // 分（人民币），叠加在基础价上

    public init(id: String, label: String, priceAddition: Int) {
        self.id = id
        self.label = label
        self.priceAddition = priceAddition
    }
}

/// 报价（用户选择规格后请求报价）。
public struct PrintQuote: Codable, Equatable, Sendable {
    public let productSpec: PrintProductSpec
    public let selectedOptionIDs: [String]
    /// 总价（分）。
    public let totalPriceCents: Int
    public let currency: String  // "CNY"
    /// 预计制作天数。
    public let estimatedProductionDays: Int
    /// 预计物流天数。
    public let estimatedShippingDays: Int

    public init(
        productSpec: PrintProductSpec, selectedOptionIDs: [String],
        totalPriceCents: Int, currency: String,
        estimatedProductionDays: Int, estimatedShippingDays: Int
    ) {
        self.productSpec = productSpec
        self.selectedOptionIDs = selectedOptionIDs
        self.totalPriceCents = totalPriceCents
        self.currency = currency
        self.estimatedProductionDays = estimatedProductionDays
        self.estimatedShippingDays = estimatedShippingDays
    }
}

/// 订单状态。
public enum PrintOrderStatus: String, Codable, Sendable {
    case pending       // 待付款
    case paid          // 已付款，制作中
    case produced      // 制作完成，待发货
    case shipped       // 已发货
    case delivered     // 已签收
    case cancelled     // 已取消
}

/// 打印订单。
public struct PrintOrder: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let productSpec: PrintProductSpec
    public let selectedOptionIDs: [String]
    public let totalPriceCents: Int
    public let currency: String
    public let status: PrintOrderStatus
    public let createdAt: Date
    /// 物流单号（发货后填充）。
    public let trackingNumber: String?
    /// 定制数据来源 ID（照片选择集 / 卡片模板 / 拼豆图纸 ID）。
    public let sourceContentID: String

    public init(
        id: String, productSpec: PrintProductSpec, selectedOptionIDs: [String],
        totalPriceCents: Int, currency: String, status: PrintOrderStatus,
        createdAt: Date, trackingNumber: String?, sourceContentID: String
    ) {
        self.id = id
        self.productSpec = productSpec
        self.selectedOptionIDs = selectedOptionIDs
        self.totalPriceCents = totalPriceCents
        self.currency = currency
        self.status = status
        self.createdAt = createdAt
        self.trackingNumber = trackingNumber
        self.sourceContentID = sourceContentID
    }
}

// MARK: - 错误

public enum PrintServiceError: Error, LocalizedError, Sendable {
    case serviceUnavailable
    case productNotFound(String)
    case quoteFailed(String)
    case orderFailed(String)
    case orderNotFound(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable:     return "打印服务暂未开放"
        case .productNotFound(let id): return "产品不存在（\(id)）"
        case .quoteFailed(let msg):    return "报价失败：\(msg)"
        case .orderFailed(let msg):    return "下单失败：\(msg)"
        case .orderNotFound(let id):   return "订单不存在（\(id)）"
        case .networkError(let msg):   return "网络错误：\(msg)"
        }
    }
}

// MARK: - 协议

/// 打印服务抽象（业务层依赖此协议，不依赖具体实现）。
public protocol PrintService: Sendable {
    /// 服务是否可用（V1 返回 false，UI 隐藏入口或显示「即将上线」）。
    var isAvailable: Bool { get }

    /// 查询全部可用产品规格目录。
    func fetchProductCatalog() async throws -> [PrintProductSpec]

    /// 按类型筛选产品。
    func fetchProducts(type: PrintProductType) async throws -> [PrintProductSpec]

    /// 请求报价。
    func requestQuote(
        productSpec: PrintProductSpec,
        selectedOptionIDs: [String]
    ) async throws -> PrintQuote

    /// 创建订单。
    func createOrder(
        productSpec: PrintProductSpec,
        selectedOptionIDs: [String],
        sourceContentID: String
    ) async throws -> PrintOrder

    /// 查询订单状态。
    func fetchOrder(id: String) async throws -> PrintOrder

    /// 查询用户全部订单。
    func fetchAllOrders() async throws -> [PrintOrder]
}

// MARK: - V1 占位实现

/// 打印服务占位实现（V1：所有方法 throw `.serviceUnavailable`）。
/// UI 层通过 `isAvailable == false` 隐藏打印入口或显示「即将上线」。
public final class UnavailablePrintService: PrintService {
    public init() {}

    public var isAvailable: Bool { false }

    public func fetchProductCatalog() async throws -> [PrintProductSpec] {
        throw PrintServiceError.serviceUnavailable
    }

    public func fetchProducts(type: PrintProductType) async throws -> [PrintProductSpec] {
        throw PrintServiceError.serviceUnavailable
    }

    public func requestQuote(
        productSpec: PrintProductSpec,
        selectedOptionIDs: [String]
    ) async throws -> PrintQuote {
        throw PrintServiceError.serviceUnavailable
    }

    public func createOrder(
        productSpec: PrintProductSpec,
        selectedOptionIDs: [String],
        sourceContentID: String
    ) async throws -> PrintOrder {
        throw PrintServiceError.serviceUnavailable
    }

    public func fetchOrder(id: String) async throws -> PrintOrder {
        throw PrintServiceError.serviceUnavailable
    }

    public func fetchAllOrders() async throws -> [PrintOrder] {
        throw PrintServiceError.serviceUnavailable
    }
}
