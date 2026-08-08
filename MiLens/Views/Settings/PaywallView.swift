//  PaywallView —— 付费墙（UI Rework 4.5，视觉按 UI-DESIGN.md §6.10）。
//
//  - 标题围绕当前创作动作，文楷只承担一次情感表达。
//  - 年费方案视觉突出：更大卡片 + 1.5pt ActionPrimary 描边 + numberStat 价格。
//  - 价格/试用天数全部来自 StoreKit Product 投影（StoreProductInfo），代码无硬编码金额（P0-4）。
//  - 底部诚实续订条款（随选中方案变化：试用/订阅/买断三种形态）+ 恢复购买 +
//    隐私政策/服务条款链接 + 关闭按钮（§6.10 必备项）。
//  - 加载失败有降级态可重试；权益只写 V1 真实能力（权益矩阵未冻结，措辞克制）。

import SwiftUI

struct PaywallView: View {
    @Environment(\.storeService) private var storeService
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.dismiss) private var dismiss
    @State private var model: PaywallViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .tint(.milensActionPrimary)
            }
        }
        .background(Color.milensBackground)
        .onAppear {
            guard model == nil else { return }
            let viewModel = PaywallViewModel(store: storeService, entitlement: entitlement)
            viewModel.onAppear()
            model = viewModel
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Sizing.iconLg))
                        .foregroundStyle(Color.milensTextTertiary)
                }
                .accessibilityLabel(String(localized: "paywall.close"))
            }
        }
    }

    @ViewBuilder
    private func content(_ model: PaywallViewModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .tint(.milensActionPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            PaywallLoadFailedState {
                Task { await model.load() }
            }
        case .ready:
            readyContent(model)
        }
    }

    // MARK: - 主内容

    private func readyContent(_ model: PaywallViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header
                benefits
                productCards(model)
                purchaseArea(model)
                footer(model)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
            .frame(maxWidth: 620)   // 表单最大可读宽度（UI-DESIGN.md §5.1）
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: model.selectedID)
        .sensoryFeedback(.success, trigger: model.purchaseMessage) { $1 == .success }
        .onChange(of: model.purchaseMessage) { _, message in
            if message == .success { dismiss() }
        }
        .alert(
            String(localized: "paywall.alert.title"),
            isPresented: alertPresented(model),
            actions: {
                Button(String(localized: "paywall.alert.ok"), role: .cancel) {
                    model.dismissMessages()
                }
            },
            message: { Text(alertText(model)) }
        )
    }

    // MARK: 头部（记忆标记 + 情感化标题）

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ArchiveMarker(label: "创作解锁")
            Text(String(localized: "paywall.title"))
                .font(.displayMedium)
                .foregroundStyle(Color.milensTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(String(localized: "paywall.subtitle"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
        }
    }

    // MARK: 权益（只写 V1 真实能力，P0-4）

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            benefitRow(text: String(localized: "paywall.benefit.export"))
            benefitRow(text: String(localized: "paywall.benefit.create"))
            benefitRow(text: String(localized: "paywall.benefit.family"))
        }
    }

    private func benefitRow(text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Sizing.iconMd))
                .foregroundStyle(Color.milensSuccess)
            Text(text)
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
        }
    }

    // MARK: 产品卡片

    private func productCards(_ model: PaywallViewModel) -> some View {
        VStack(spacing: Spacing.md) {
            ForEach(model.products) { product in
                PaywallProductCard(
                    product: product,
                    isSelected: model.selectedID == product.id,
                    isFeatured: PaywallLogic.isFeatured(product)
                ) {
                    model.selectedID = product.id
                }
            }
        }
    }

    // MARK: 购买区（CTA + 条款）

    private func purchaseArea(_ model: PaywallViewModel) -> some View {
        VStack(spacing: Spacing.md) {
            if model.proStatus.isActive {
                Label(String(localized: "paywall.pro.owned"), systemImage: "checkmark.seal.fill")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensSuccess)
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                Button {
                    Task { await model.purchaseSelected() }
                } label: {
                    Group {
                        if model.isPurchasing {
                            ProgressView()
                                .tint(Color.milensTextOnActionPrimary)
                        } else {
                            Text(ctaTitle(for: model))
                                .font(.buttonLabel)
                        }
                    }
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.milensActionPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(PaywallLogic.ctaKind(for: model.selectedProduct) == .unavailable || model.isPurchasing)
            }

            Text(termsText(for: model))
                .font(.caption)
                .foregroundStyle(Color.milensTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// CTA 文案：试用天数/价格均来自 Product 投影。
    private func ctaTitle(for model: PaywallViewModel) -> String {
        switch PaywallLogic.ctaKind(for: model.selectedProduct) {
        case .trial(let days):
            return String(format: String(localized: "paywall.cta.trial"), days)
        case .subscribe:
            return String(
                format: String(localized: "paywall.cta.subscribe.price"),
                model.selectedProduct?.displayPrice ?? ""
            )
        case .lifetime:
            return String(
                format: String(localized: "paywall.cta.lifetime.price"),
                model.selectedProduct?.displayPrice ?? ""
            )
        case .unavailable:
            return String(localized: "paywall.cta.unavailable")
        }
    }

    /// 诚实续订条款：随选中方案形态变化（§6.10）。
    private func termsText(for model: PaywallViewModel) -> String {
        let product = model.selectedProduct
        switch PaywallLogic.termsKind(for: product) {
        case .trialSubscription:
            return String(
                format: String(localized: "paywall.terms.trial"),
                product?.trialDays ?? 0,
                product?.displayPrice ?? ""
            )
        case .plainSubscription:
            return String(
                format: String(localized: "paywall.terms.subscription"),
                product?.displayPrice ?? ""
            )
        case .lifetime:
            return String(localized: "paywall.terms.lifetime")
        }
    }

    // MARK: 底部（恢复购买 + 法务链接）

    private func footer(_ model: PaywallViewModel) -> some View {
        VStack(spacing: Spacing.md) {
            Button(String(localized: "paywall.restore")) {
                Task { await model.restore() }
            }
            .disabled(model.isRestoring)

            if let url = URL(string: SettingsLogic.Links.privacyPolicy) {
                Link(String(localized: "paywall.link.privacy"), destination: url)
            }
            if let url = URL(string: SettingsLogic.Links.termsOfService) {
                Link(String(localized: "paywall.link.terms"), destination: url)
            }
        }
        .font(.caption)
        .foregroundStyle(Color.milensTextSecondary)
        .frame(maxWidth: .infinity)
    }

    // MARK: 提示

    private func alertPresented(_ model: PaywallViewModel) -> Binding<Bool> {
        Binding(
            get: {
                if let purchase = model.purchaseMessage,
                   purchase != .silent, purchase != .success { return true }
                return model.restoreMessage != nil
            },
            set: { if !$0 { model.dismissMessages() } }
        )
    }

    private func alertText(_ model: PaywallViewModel) -> String {
        if let restore = model.restoreMessage {
            switch restore {
            case .restored: return String(localized: "paywall.restore.done")
            case .nothingToRestore: return String(localized: "paywall.restore.none")
            case .failed: return String(localized: "paywall.restore.failed")
            }
        }
        switch model.purchaseMessage {
        case .pending: return String(localized: "paywall.purchase.pending")
        case .failed: return String(localized: "paywall.purchase.failed")
        default: return ""
        }
    }
}

// MARK: - 产品卡片

private struct PaywallProductCard: View {
    let product: StoreProductInfo
    let isSelected: Bool
    let isFeatured: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Text(product.displayName)
                            .font(isFeatured ? .titleStandard : .bodyPrimary)
                            .foregroundStyle(Color.milensTextPrimary)
                        if isFeatured {
                            Text(String(localized: "paywall.badge.recommended"))
                                .font(.caption)
                                .foregroundStyle(Color.milensActionPrimary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.milensAccentSoft)
                                .clipShape(Capsule())
                        }
                    }
                    if let trialDays = product.trialDays {
                        Text(String(format: String(localized: "paywall.trial.hint"), trialDays))
                            .font(.caption)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text(product.displayPrice)
                        .font(isFeatured ? .numberStat : .titleStandard)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(periodText)
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, isFeatured ? Spacing.xl : Spacing.lg)
            .background(isSelected ? Color.milensAccentSoft : Color.milensCard)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .stroke(
                        isSelected ? Color.milensActionPrimary : Color.milensBorder,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var periodText: String {
        switch product.period {
        case .monthly: return String(localized: "paywall.period.monthly")
        case .yearly: return String(localized: "paywall.period.yearly")
        case .lifetime: return String(localized: "paywall.period.once")
        case .other: return ""
        }
    }
}

// MARK: - 加载失败降级态

private struct PaywallLoadFailedState: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.milensTextSecondary)
            Text(String(localized: "paywall.load.failed"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "paywall.retry"), action: retry)
                .font(.buttonLabel)
                .buttonStyle(.borderedProminent)
                .tint(Color.milensActionPrimary)
        }
        .padding(.horizontal, Spacing.pagePad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
