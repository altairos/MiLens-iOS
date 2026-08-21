//  PaywallPurchaseDisclosure —— Paywall 购买前法律与价格披露。
//
//  将价格、计费周期、试用/续费、重大条款和两份法律文档同意集中放在购买 CTA 之前。
//  价格与试用天数始终来自 StoreProductInfo，不在 UI 中硬编码。

import SwiftUI

struct PaywallPurchaseDisclosure: View {
    let model: PaywallViewModel
    @Binding var legalAgreed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "paywall.disclosure.title"))
                .font(.uiBodyStrong)
                .foregroundStyle(Color.milensTextPrimary)

            if let product = model.selectedProduct {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    disclosureRow(
                        label: String(localized: "paywall.disclosure.price"),
                        value: product.displayPrice
                    )
                    disclosureRow(
                        label: String(localized: "paywall.disclosure.period"),
                        value: periodText(for: product)
                    )
                    if let trial = product.trialDays, trial > 0, product.period != .lifetime {
                        disclosureRow(
                            label: String(localized: "paywall.disclosure.trial"),
                            value: String(localized: "paywall.trial.hint \(trial)")
                        )
                    }
                }
            }

            if !termsText.isEmpty {
                Text(termsText)
                    .font(.bodyPrimary.weight(.semibold))
                    .foregroundStyle(Color.milensInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "paywall.important.terms"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.milensAccentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !model.proStatus.isActive {
                legalAgreement
            }
        }
        .padding(.horizontal, Spacing.pagePad)
    }

    private func disclosureRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
            Spacer(minLength: Spacing.md)
            Text(value)
                .font(.bodyPrimary.weight(.semibold))
                .foregroundStyle(Color.milensTextPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func periodText(for product: StoreProductInfo) -> String {
        switch product.period {
        case .monthly: return String(localized: "paywall.period.monthly")
        case .yearly: return String(localized: "paywall.period.yearly")
        case .lifetime: return String(localized: "paywall.period.lifetime")
        case .other: return product.displayName
        }
    }

    private var legalAgreement: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Button {
                legalAgreed.toggle()
            } label: {
                Image(systemName: legalAgreed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(legalAgreed ? Color.milensActionPrimary : Color.milensTextSecondary)
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "paywall.purchase.agreement"))
            .accessibilityValue(legalAgreed
                                ? String(localized: "common.selected")
                                : String(localized: "common.notSelected"))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "onboarding.welcome.agreePrefix"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                HStack(spacing: 4) {
                    if let termsURL = URL(string: SettingsLogic.Links.termsOfService) {
                        Link(String(localized: "paywall.link.terms"), destination: termsURL)
                    }
                    Text(String(localized: "paywall.purchase.and"))
                        .foregroundStyle(Color.milensTextTertiary)
                    if let privacyURL = URL(string: SettingsLogic.Links.privacyPolicy) {
                        Link(String(localized: "paywall.link.privacy"), destination: privacyURL)
                    }
                }
                .font(.bodySecondary.weight(.semibold))
                .foregroundStyle(Color.milensActionPrimary)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var termsText: String {
        guard let product = model.selectedProduct else { return "" }
        switch PaywallLogic.termsKind(for: product) {
        case .trialSubscription:
            return String(
                format: String(localized: "paywall.terms.trial"),
                product.trialDays ?? 0,
                product.displayPrice
            )
        case .plainSubscription:
            return String(
                format: String(localized: "paywall.terms.subscription"),
                product.displayPrice
            )
        case .lifetime:
            return String(localized: "paywall.terms.lifetime")
        }
    }
}
