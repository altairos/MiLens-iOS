//  PaywallLogic —— 付费墙纯决策逻辑（无 IO / 无 SwiftUI 依赖，DESIGN.md §4）。
//
//  决策全部基于 StoreProductInfo 投影（价格/试用来自 StoreKit Product）：
//  展示排序（年度优先）、默认选中、CTA 形态、续订条款形态、购买/恢复结果文案选择。
//  View 层只负责按返回的枚举取本地化文案渲染。

import Foundation

enum PaywallLogic {

    // MARK: - 展示排序与选中

    /// 展示排序：年度优先（视觉突出，UI-DESIGN 付费墙规范），其次月度，最后永久买断，其余兜底。
    static func orderedForDisplay(_ products: [StoreProductInfo]) -> [StoreProductInfo] {
        products.sorted { lhs, rhs in
            rank(of: lhs.period) < rank(of: rhs.period)
        }
    }

    /// 默认选中：年度方案；无年度时取排序后第一个。
    static func defaultSelectionID(_ products: [StoreProductInfo]) -> String? {
        let ordered = orderedForDisplay(products)
        return ordered.first { $0.period == .yearly }?.id ?? ordered.first?.id
    }

    /// 年度方案视觉突出（描边/更大卡片）。
    static func isFeatured(_ product: StoreProductInfo) -> Bool {
        product.period == .yearly
    }

    private static func rank(of period: StoreProductPeriod) -> Int {
        switch period {
        case .yearly: return 0
        case .monthly: return 1
        case .lifetime: return 2
        case .other: return 3
        }
    }

    // MARK: - CTA 形态

    enum CTAKind: Equatable {
        /// 有免费试用：按钮突出试用天数（价格仍在卡片上紧邻展示）
        case trial(days: Int)
        /// 订阅无试用：按钮带价格（来自 Product.displayPrice）
        case subscribe
        /// 永久买断：按钮带价格
        case lifetime
        /// 未选中/无产品：禁用
        case unavailable
    }

    static func ctaKind(for product: StoreProductInfo?) -> CTAKind {
        guard let product else { return .unavailable }
        if let days = product.trialDays, days > 0, product.period != .lifetime {
            return .trial(days: days)
        }
        return product.period == .lifetime ? .lifetime : .subscribe
    }

    // MARK: - 续订条款形态

    enum TermsKind: Equatable {
        /// 订阅含免费试用：说明试用天数 + 之后按价续费
        case trialSubscription
        /// 订阅无试用：说明按价自动续费
        case plainSubscription
        /// 永久买断：一次购买无后续费用
        case lifetime
    }

    static func termsKind(for product: StoreProductInfo?) -> TermsKind {
        guard let product else { return .plainSubscription }
        if product.period == .lifetime { return .lifetime }
        if let days = product.trialDays, days > 0 { return .trialSubscription }
        return .plainSubscription
    }

    // MARK: - 购买/恢复结果 → 用户提示

    enum PurchaseMessage: Equatable {
        /// 用户取消：不提示
        case silent
        /// 购买成功（View 负责关闭付费墙 + 成功触感）
        case success
        /// 购买挂起（需监护人批准等）
        case pending
        /// 购买失败（含验证失败）
        case failed
    }

    static func message(for outcome: StorePurchaseOutcome) -> PurchaseMessage {
        switch outcome {
        case .success: return .success
        case .userCancelled: return .silent
        case .pending: return .pending
        }
    }

    enum RestoreMessage: Equatable {
        case restored
        case nothingToRestore
        case failed
    }

    static func message(restoredTo status: ProStatus) -> RestoreMessage {
        status.isActive ? .restored : .nothingToRestore
    }
}
