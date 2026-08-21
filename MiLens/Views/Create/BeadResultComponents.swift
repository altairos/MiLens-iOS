//  BeadResultComponents —— 拼豆结果页输出面板组件。
//  从 BeadPatternResultView 拆出（规模守卫，DESIGN.md §6 / AGENTS.md §3）。
//  对照 Figma #313:1428-1448（Export Inspector · Archive Output）。

import SwiftUI

/// 作品输出面板：HD 保存 / 分享 / A4 图纸 + Darkroom Pulse 导出按钮。
/// 复用与 exportDock 相同的导出逻辑（onExport / onShare）。
struct BeadResultOutputPanel: View {
    let isExporting: Bool
    let onExport: () -> Void
    let onShare: () -> Void
    let onA4Export: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "bead.result.overline"))
                .font(.custom("JacquesFrancois-Regular", size: 10))
                .tracking(0.4)
                .foregroundStyle(Color.milensActionPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 18)

            Text(String(localized: "bead.result.keepTitle"))
                .font(.localeDisplayFont(size: 20))
                .foregroundStyle(Color.milensTextPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 14)

            // 输出选项列表（对照 #313:1430-1447）
            outputRow(title: String(localized: "create.bead.saveHd"),
                      desc: String(localized: "bead.result.saveHdDesc"), badge: nil,
                      action: onExport)
            outputSeparator

            outputRow(title: String(localized: "bead.result.shareTitle"),
                      desc: String(localized: "bead.result.shareDesc"), badge: nil,
                      action: onShare)
            outputSeparator

            outputRow(title: String(localized: "bead.result.a4Title"),
                      desc: String(localized: "bead.result.a4Desc"), badge: "PRO",
                      action: onA4Export)
            outputSeparator

            // Darkroom Pulse 导出按钮（对照 #313:1448）
            Button {
                onExport()
            } label: {
                Group {
                    if isExporting {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text(String(localized: "create.bead.exporting"))
                                .font(.buttonLabel)
                                .foregroundStyle(.white)
                        }
                    } else {
                        Text(String(localized: "create.bead.saveHd"))
                            .font(.buttonLabel)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 输出选项行（对照 #313:1430-1446）
    private func outputRow(title: String, desc: String, badge: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(desc)
                        .font(.editorialOverline)
                        .foregroundStyle(Color.milensTextTertiary)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensActionPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.milensAccentSoft)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
    }

    private var outputSeparator: some View {
        Rectangle()
            .fill(Color.milensBorder)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}
