//  PrivacyInfoView —— 本地数据与隐私说明（Settings 数据与隐私分组入口）。
//
//  三条本地处理承诺与 Onboarding 说明页口径一致（UI-DESIGN.md §6.1/§6.9）；
//  隐私政策链接与系统权限管理入口；数据存储与删除说明（清理与删除严格分离的前提说明）。

import SwiftUI

struct PrivacyInfoView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.marketProfile) private var marketProfile

    var body: some View {
        List {
            Section {
                ForEach(PrivacyNarrativeLogic.commitmentKinds(for: marketProfile)) { kind in
                    commitmentRow(for: kind)
                }
            } header: {
                Text(String(localized: "privacy.commit.title"))
            }

            Section {
                Text(String(localized: "privacy.storage.detail"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            } header: {
                Text(String(localized: "privacy.storage.title"))
            }

            Section {
                if let url = URL(string: SettingsLogic.Links.privacyPolicy) {
                    Link(destination: url) {
                        Label(String(localized: "privacy.policy.link"), systemImage: "doc.text")
                    }
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label(String(localized: "privacy.permissions.manage"), systemImage: "gear")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.milensBackground)
        .navigationTitle(String(localized: "settings.privacy.local"))
    }

    /// 根据承诺类型映射到 String Catalog key（保持编译时 key 检查）。
    private func commitmentRow(for kind: PrivacyCommitKind) -> some View {
        let title: String
        let detail: String
        switch kind {
        case .ondevice:
            title = String(localized: "privacy.commit.ondevice")
            detail = String(localized: "privacy.commit.ondevice.detail")
        case .local:
            title = String(localized: "privacy.commit.local")
            detail = String(localized: "privacy.commit.local.detail")
        case .control:
            title = String(localized: "privacy.commit.control")
            detail = String(localized: "privacy.commit.control.detail")
        case .gdpr:
            title = String(localized: "privacy.commit.gdpr")
            detail = String(localized: "privacy.commit.gdpr.detail")
        }
        return commitmentRow(icon: kind.icon, title: title, detail: detail)
    }

    private func commitmentRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: Sizing.iconMd))
                .foregroundStyle(Color.milensActionPrimary)
                .frame(width: Sizing.iconLg)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(detail)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
