//  PaywallView —— 付费墙（对照 Figma「06·MiLens Pro」#58:25）。
//
//  全屏暗色照片背景 + 顶部文楷标题 + 底部白色 Purchase Sheet（珊瑚竖线 rail +
//  权益行 + 方案行 + 暗色 CTA + 箭头印章）。
//  ViewModel / PaywallLogic / StoreKit 零改动，所有绑定保持。
//  价格/试用天数全部来自 StoreKit Product 投影（StoreProductInfo），代码无硬编码金额（P0-4）。

import SwiftUI
import MiLensKit

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
        .onAppear {
            MetricsRecorder().record(.paywallShown)
            guard model == nil else { return }
            let viewModel = PaywallViewModel(store: storeService, entitlement: entitlement)
            viewModel.onAppear()
            model = viewModel
        }
    }

    @ViewBuilder
    private func content(_ model: PaywallViewModel) -> some View {
        switch model.phase {
        case .loading:
            ZStack {
                Color.milensStudioBackground.ignoresSafeArea()
                ProgressView()
                    .tint(.milensActionPrimary)
            }
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
        ZStack(alignment: .bottom) {
            // 上半屏：暗色背景 + 标题区
            heroSection
                .ignoresSafeArea(edges: .top)

            // 关闭按钮
            closeButton
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.trailing, Spacing.md)
                .padding(.top, 13)

            // 下半屏：Purchase Sheet
            purchaseSheet(model)
        }
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

    // MARK: - 上半屏 Hero 区

    /// 全屏暗色背景 + MiLens Pro + 文楷标题 + 副标题。
    /// 对照 Figma #64:416-423。
    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            // 暗色渐变底（纯色兜底，不依赖具体照片资源）
            LinearGradient(
                colors: [
                    Color.milensPaywallGradientStart.opacity(0.85),
                    Color.milensPaywallGradientEnd.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 顶部标题区
            VStack(alignment: .leading, spacing: 0) {
                Text("MiLens Pro")
                    .font(.custom("Fraunces-Semibold", size: 24))
                    .foregroundStyle(.white)
                    .padding(.top, 61)

                Text(String(localized: "paywall.hero.title"))
                    .font(.custom("LXGWWenKai-Regular", size: 37, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.lg)

                Text(String(localized: "paywall.hero.subtitle"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensPaywallSubtitle)
                    .padding(.top, Spacing.lg)

                // 副标题（对照 Figma #37:29）
                Text("更多伙伴 · 完整回顾 · 高质量导出")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensDarkroomText)
                    .padding(.top, 4)

                Spacer()
            }
            .padding(.horizontal, Spacing.pagePad)
        }
    }

    // MARK: - 关闭按钮（对照 Figma #64:418）

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 44, height: 44)
                Image(systemName: "xmark")
                    .font(.system(size: Sizing.iconSm, weight: .semibold))
                    .foregroundStyle(Color.milensInk)
            }
        }
        .accessibilityLabel(String(localized: "paywall.close"))
    }

    // MARK: - 下半屏 Purchase Sheet（对照 Figma #64:424）

    private func purchaseSheet(_ model: PaywallViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            Text(String(localized: "paywall.purchase.title"))
                .font(.uiTitle)
                .foregroundStyle(Color.milensTextPrimary)
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.xl)

            // 权益区（3 项 + 珊瑚竖线 rail）
            benefitsSection
                .padding(.top, Spacing.xl)

            // 方案选择
            planSection(model)
                .padding(.top, Spacing.xl)

            // CTA
            purchaseButton(model)
                .padding(.top, Spacing.lg)

            // 底部页脚链接
            footerLinks
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.lg)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 0)
        .shadow(color: .black.opacity(0.15), radius: 20, y: -4)
    }

    // MARK: - 权益区（珊瑚竖线 + 3 项，对照 Figma #327:691 + #64:426-437）

    private var benefitsSection: some View {
        HStack(alignment: .top, spacing: 0) {
            // 珊瑚竖线 rail（2pt，对照 Benefit Rail #327:691）
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 2)
                .padding(.leading, 31)

            // 权益列表
            VStack(alignment: .leading, spacing: 0) {
                benefitRow(
                    title: "不限照片数量",
                    desc: "继续导入每一段回忆"
                )
                benefitDivider
                benefitRow(
                    title: "把时间整理成生命章节",
                    desc: "年度回顾按真实日期生成"
                )
                benefitDivider
                benefitRow(
                    title: "作品与原片都能高质量带走",
                    desc: "高清导出照片、记忆与作品"
                )
            }
            .padding(.leading, 12)
            .padding(.trailing, Spacing.pagePad)
        }
    }

    private func benefitRow(title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 珊瑚圆点 8pt（对照 Benefit Icon #64:426）
            Circle()
                .fill(Color.milensActionPrimary)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(desc)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
        .padding(.vertical, 12)
    }

    private var benefitDivider: some View {
        Rectangle()
            .fill(Color.milensBorder)
            .frame(height: 0.5)
            .padding(.leading, 20)
    }

    // MARK: - 方案选择（对照 Figma #64:438-444）

    private func planSection(_ model: PaywallViewModel) -> some View {
        VStack(spacing: 0) {
            ForEach(model.products) { product in
                planRow(product: product, isSelected: model.selectedID == product.id) {
                    model.selectedID = product.id
                }
                if product != model.products.last {
                    Rectangle()
                        .fill(Color.milensBorder)
                        .frame(height: 0.5)
                        .padding(.leading, 72)
                }
            }
        }
        .padding(.horizontal, Spacing.pagePad)
    }

    private func planRow(product: StoreProductInfo, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // 选中圈（对照 Annual Selected #64:439）
                ZStack {
                    Circle()
                        .stroke(Color.milensActionPrimary, lineWidth: 2)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(Color.milensActionPrimary)
                            .frame(width: 10, height: 10)
                    }
                }
                .frame(width: 24, height: 24)

                // 方案名称
                Text(planName(for: product))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)

                Spacer()

                // 右侧：试用/价格信息（对照 Figma #37:49/51）
                VStack(alignment: .trailing, spacing: 2) {
                    if isSelected, let trial = product.trialDays, trial > 0 {
                        Text(String(localized: "paywall.trial.hint \(trial)"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                    Text("从 App Store 获取")
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, isSelected ? 18 : 14)
            .background(isSelected ? Color.milensAccentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 从 StoreProductInfo 推导方案显示名。
    private func planName(for product: StoreProductInfo) -> String {
        switch product.period {
        case .yearly: return String(localized: "paywall.plan.annual")
        case .monthly: return String(localized: "paywall.plan.monthly")
        default: return product.displayName
        }
    }

    // MARK: - CTA 按钮（对照 Figma #64:446 + #328:693）

    @ViewBuilder
    private func purchaseButton(_ model: PaywallViewModel) -> some View {
        if model.proStatus.isActive {
            // 已解锁状态
            Label(String(localized: "paywall.pro.owned"), systemImage: "checkmark.seal.fill")
                .font(.buttonLabel)
                .foregroundStyle(Color.milensSuccess)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.milensBorder, lineWidth: 0.5))
                .padding(.horizontal, Spacing.pagePad)
        } else {
            Button {
                Task { await model.purchaseSelected() }
            } label: {
                HStack {
                    Text(ctaTitle(for: model))
                        .font(.buttonLabel)
                        .foregroundStyle(Color.milensDarkroomText)
                    Spacer()
                    // 箭头印章（对照 Purchase Seal #328:693）
                    ZStack {
                        Circle()
                            .fill(Color.milensSealSurface)
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(Color.milensActionPrimary, lineWidth: 2)
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.right")
                            .font(.system(size: Sizing.iconSm, weight: .medium))
                            .foregroundStyle(Color.milensDarkroomText)
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color.milensInk)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.milensActionPrimary, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(PaywallLogic.ctaKind(for: model.selectedProduct) == .unavailable || model.isPurchasing)
            .padding(.horizontal, Spacing.pagePad)
        }

        // 续订条款（随选中方案变化）
        Text(termsText(for: model))
            .font(.caption)
            .foregroundStyle(Color.milensTextTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.sm)
    }

    /// CTA 文案：试用天数/价格均来自 Product 投影。
    private func ctaTitle(for model: PaywallViewModel) -> String {
        switch PaywallLogic.ctaKind(for: model.selectedProduct) {
        case .trial(let days):
            return String(localized: "paywall.cta.trial \(days)")
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

    // MARK: - 底部页脚（对照 Figma #64:448）

    private var footerLinks: some View {
        HStack(spacing: 0) {
            Button(String(localized: "paywall.restore")) {
                if let model { Task { await model.restore() } }
            }
            Text("   ·   ")
                .foregroundStyle(Color.milensTextTertiary)
            if let url = URL(string: SettingsLogic.Links.termsOfService) {
                Link(String(localized: "paywall.link.terms"), destination: url)
            }
            Text("   ·   ")
                .foregroundStyle(Color.milensTextTertiary)
            if let url = URL(string: SettingsLogic.Links.privacyPolicy) {
                Link(String(localized: "paywall.link.privacy"), destination: url)
            }
        }
        .font(.editorialMetadata)
        .foregroundStyle(Color.milensTextSecondary)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 提示

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

// MARK: - 加载失败降级态

private struct PaywallLoadFailedState: View {
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color.milensStudioBackground.ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 40, weight: .light)) // ui-token:ok 错误态装饰大图标
                    .foregroundStyle(Color.milensPaper.opacity(0.5))
                Text(String(localized: "paywall.load.failed"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensPaper)
                    .multilineTextAlignment(.center)
                Button(String(localized: "paywall.retry"), action: retry)
                    .font(.buttonLabel)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.milensActionPrimary)
            }
            .padding(.horizontal, Spacing.pagePad)
        }
    }
}
