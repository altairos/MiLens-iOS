//  RedPacketTemplatePickerView —— 红包模板选择页（对应红包封面开发计划 §2.1）。
//
//  展示 4 套风格模板的缩略图（用 RedPacketCoverRenderer 渲染无宠物默认预览）+ 风格名。
//  选中后进入照片选择页。模板切换时保留照片、抠图结果和文本内容（在工作室页处理）。

import SwiftUI
import MiLensKit

struct RedPacketTemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.proEntitlement) private var entitlement

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "redpacket.workshop.templatePicker")) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "redpacket.workshop.chooseTemplate"))
                        .font(.editorialSection)
                        .foregroundStyle(Color.milensTextPrimary)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.lg)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(RedPacketTemplateCatalog.all) { template in
                            templateCard(template)
                        }
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.xxl)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - 模板卡片

    private func templateCard(_ template: RedPacketTemplate) -> some View {
        let isLocked = !template.isFree && !entitlement.isPro
        return NavigationLink(value: Route.redPacketPhotoPicker(templateID: template.id)) {
            VStack(spacing: 0) {
                // 缩略图预览
                RedPacketCoverRenderer(
                    template: template,
                    layers: rpDefaultLayers(for: template),
                    petImage: nil,
                    includeWatermark: false
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                            .padding(6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if template.isFree {
                        Text(String(localized: "redpacket.template.free"))
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.milensActionPrimary)
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }

                // 风格名（模板层只存 key，App 层从 xcstrings 取）
                Text(String(localized: String.LocalizationValue(template.displayNameKey)))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }
}

#Preview {
    NavigationStack {
        RedPacketTemplatePickerView()
    }
}
