//  RedPacketQualityReportView —— 画面检查页（对应 Figma #6 Red Packet / Quality Check · Refined）。
//
//  紧凑封面预览 + 五维检测结果表 + 优化状态卡（优化前/后切换 + 撤销本次调整）。
//  Figma 控件已恢复，代码侧补了 preOptimizationLayers 快照切换状态。

import SwiftUI
import MiLensKit

struct RedPacketQualityReportView: View {
    @Bindable var viewModel: RedPacketWorkshopViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            navHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    previewSection
                    qualityPanel
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.milensBackground)
        .task {
            viewModel.evaluateQuality()
        }
    }

    // MARK: - 导航头

    private var navHeader: some View {
        WorkshopNavHeader(title: String(localized: "redpacket.quality.title")) {
            dismiss()
        } trailing: {
            Button {
                dismiss()
            } label: {
                Text(String(localized: "redpacket.quality.done"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensActionPrimary)
            }
        }
    }

    // MARK: - 紧凑预览 + 评分轨

    private var previewSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // 封面预览
            RedPacketCoverRenderer(
                template: viewModel.template,
                layers: displayLayers,
                petImage: viewModel.cutoutImage,
                includeWatermark: !viewModel.isPro
            )
            .frame(width: 160, height: 213)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // 评分轨
            scoreRail
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.md)
    }

    /// 当前显示的图层（优化前预览时使用快照）。
    private var displayLayers: [RedPacketLayer] {
        if viewModel.isPreviewingBeforeOptimization, let before = viewModel.preOptimizationLayers {
            return before
        }
        return viewModel.layers
    }

    // MARK: - 评分轨

    private var scoreRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 评分
            let passCount = viewModel.qualityReport?.items.filter { $0.level == .pass }.count ?? 0
            let totalCount = viewModel.qualityReport?.items.count ?? 5

            Text("QUALITY")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.milensTextSecondary)
            Text("\(passCount) / \(totalCount)")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(passCount == totalCount ? Color.milensActionPrimary : Color.milensTextPrimary)
            Text(passCount == totalCount
                 ? String(localized: "redpacket.quality.allGood")
                 : String(localized: "redpacket.quality.hasIssues"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.milensTextPrimary)

            Divider()
                .padding(.vertical, 8)

            // 本次调整摘要
            if viewModel.hasAppliedOptimization {
                Text(String(localized: "redpacket.quality.thisAdjustment"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.milensTextSecondary)
                Text(viewModel.optimizationSummary.isEmpty
                     ? String(localized: "redpacket.optimize.applied")
                     : adjustmentSummary())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.milensTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text(String(localized: "redpacket.quality.onlySuggestion"))
                .font(.system(size: 11))
                .foregroundStyle(Color.milensTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // 重新检测
            Button {
                viewModel.evaluateQuality()
            } label: {
                VStack(spacing: 4) {
                    Text(String(localized: "redpacket.quality.recheck"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.milensActionPrimary)
                    Rectangle()
                        .fill(Color.milensSeparator)
                        .frame(width: 68, height: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 智能检测面板

    @ViewBuilder
    private var qualityPanel: some View {
        VStack(spacing: 0) {
            // 铜色索引条
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 64, height: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Spacing.pagePad)

            // 面板头
            HStack {
                Text(String(localized: "redpacket.quality.intelligentCheck"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text(String(localized: "redpacket.quality.completed"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.sm)

            // 五维结果表
            if let report = viewModel.qualityReport {
                fiveDimensionResults(report: report)
            }

            // 优化状态卡（仅在已应用优化时显示）
            if viewModel.hasAppliedOptimization {
                optimizationStateCard
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.md)

                // 优化前/后切换 + 撤销本次调整
                beforeAfterControls
            }

            // 免责声明
            Text(String(localized: "redpacket.optimize.disclaimer"))
                .font(.system(size: 10))
                .foregroundStyle(Color.milensTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.sm)
        }
        .padding(.top, Spacing.lg)
    }

    // MARK: - 五维结果表

    private func fiveDimensionResults(report: RedPacketQualityReport) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(report.items.enumerated()), id: \.element.id) { index, item in
                qualityRow(item: item, isLast: index == report.items.count - 1)
            }
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.sm)
    }

    private func qualityRow(item: RedPacketQualityItem, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // 左侧铜色标记（仅已调整的行）
                Rectangle()
                    .fill(item.level != .pass ? Color.milensActionPrimary : Color.clear)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))

                Text(dimensionName(item.dimension))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.milensTextPrimary)
                    .frame(width: 58, alignment: .leading)
                    .padding(.leading, 9)

                Text(item.detail.isEmpty ? "—" : item.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.milensTextSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(statusText(item.level))
                    .font(.system(size: 11, weight: item.level != .pass ? .medium : .regular))
                    .foregroundStyle(item.level != .pass ? Color.milensActionPrimary : Color.milensTextSecondary)
                    .frame(width: 80, alignment: .trailing)
            }
            .frame(height: 30)

            if !isLast {
                Rectangle()
                    .fill(Color.milensSeparator.opacity(0.5))
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: - 优化状态卡

    private var optimizationStateCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 左侧铜色竖条
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    // 头行
                    HStack {
                        Text(String(localized: "redpacket.optimize.suggestTitle"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.milensTextPrimary)
                        Spacer()
                        Text(String(localized: "redpacket.optimize.applied"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.milensActionPrimary)
                    }

                    // 调整详情
                    Text(adjustmentSummary())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.milensTextPrimary)

                    // 补充说明
                    Text(String(localized: "redpacket.optimize.noSourceChange"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.milensTextSecondary)
                }
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color.milensSealSurface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.milensActionPrimary.opacity(0.38), lineWidth: 1)
        )
        .padding(.top, Spacing.sm)
        // 优化前/后切换 + 撤销按钮
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {}
        }
    }

    // MARK: - 辅助

    private func dimensionName(_ dimension: RedPacketQualityDimension) -> String {
        switch dimension {
        case .clarity: return String(localized: "redpacket.quality.dim.clarity")
        case .brightness: return String(localized: "redpacket.quality.dim.brightness")
        case .composition: return String(localized: "redpacket.quality.dim.composition")
        case .cutout: return String(localized: "redpacket.quality.dim.cutout")
        case .readability: return String(localized: "redpacket.quality.dim.readability")
        }
    }

    private func statusText(_ level: RedPacketQualityLevel) -> String {
        switch level {
        case .pass: return String(localized: "redpacket.quality.status.pass")
        case .warning: return String(localized: "redpacket.quality.status.warning")
        case .error: return String(localized: "redpacket.quality.status.error")
        }
    }

    private func adjustmentSummary() -> String {
        if viewModel.optimizationSummary.isEmpty {
            return String(localized: "redpacket.optimize.applied")
        }
        // 映射 key 到中文
        viewModel.optimizationSummary.map { key in
            switch key {
            case "redpacket.optimize.sharpened": return String(localized: "redpacket.optimize.summary.sharpened")
            case "redpacket.optimize.brightened": return String(localized: "redpacket.optimize.summary.brightened")
            case "redpacket.optimize.contrastAdjusted": return String(localized: "redpacket.optimize.summary.contrast")
            case "redpacket.optimize.petRepositioned": return String(localized: "redpacket.optimize.summary.petPos")
            case "redpacket.optimize.textRepositioned": return String(localized: "redpacket.optimize.summary.textPos")
            case "redpacket.optimize.gentleApplied": return String(localized: "redpacket.optimize.summary.gentle")
            default: return ""
            }
        }.joined(separator: "，")
    }
}

// MARK: - 优化前/后切换 + 撤销控件（嵌入 qualityPanel 底部）

private extension RedPacketQualityReportView {

    var beforeAfterControls: some View {
        Group {
            if viewModel.hasAppliedOptimization {
                HStack(spacing: 8) {
                    // 优化前/后切换
                    HStack(spacing: 0) {
                        beforeAfterButton(
                            title: String(localized: "redpacket.optimize.before"),
                            isSelected: viewModel.isPreviewingBeforeOptimization
                        ) {
                            viewModel.isPreviewingBeforeOptimization = true
                        }
                        Rectangle()
                            .fill(Color.milensSeparator)
                            .frame(width: 1)
                        beforeAfterButton(
                            title: String(localized: "redpacket.optimize.after"),
                            isSelected: !viewModel.isPreviewingBeforeOptimization
                        ) {
                            viewModel.isPreviewingBeforeOptimization = false
                        }
                    }
                    .background(Color.milensSealSurface.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.milensSeparator, lineWidth: 1)
                    )
                    .frame(width: 222, height: 44)

                    // 撤销本次调整
                    Button {
                        viewModel.undoOptimization()
                    } label: {
                        Text(String(localized: "redpacket.optimize.undoThis"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.milensTextPrimary)
                            .frame(maxWidth: .infinity, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.milensSeparator, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.sm)
            }
        }
    }

    func beforeAfterButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.milensTextSecondary)
                .frame(maxWidth: .infinity, height: 44)
                .background(isSelected ? Color.milensActionPrimary : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
