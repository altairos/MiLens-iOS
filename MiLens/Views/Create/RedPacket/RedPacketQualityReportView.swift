//  RedPacketQualityReportView —— 质量报告 UI（对应红包封面开发计划 §4）。
//
//  展示 5 维质量检测结果 + 一键智能优化按钮。
//  检测失败可诊断、优化可撤销，不承诺平台审核通过。

import SwiftUI
import MiLensKit

struct RedPacketQualityReportView: View {
    @Bindable var viewModel: RedPacketWorkshopViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let report = viewModel.qualityReport {
                        qualitySummary(report: report)
                        qualityList(report: report)
                    } else {
                        notEvaluatedView
                    }
                }
                .padding()
            }
            Divider()
            bottomBar
        }
        .background(Color.milensBackground)
        .presentationDetents([.medium, .large])
    }

    // MARK: - 头部

    private var header: some View {
        HStack {
            Text(String(localized: "redpacket.quality.title"))
                .font(.uiBodyStrong)
            Spacer()
            Button {
                viewModel.evaluateQuality()
            } label: {
                Label(String(localized: "redpacket.quality.recheck"), systemImage: "arrow.clockwise")
                    .font(.editorialMetadata)
            }
        }
        .padding()
    }

    // MARK: - 质量摘要

    private func qualitySummary(report: RedPacketQualityReport) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(levelColor(report.overallLevel))
                .frame(width: 12, height: 12)
            Text(levelText(report.overallLevel))
                .font(.uiBodyStrong)
                .foregroundStyle(Color.milensTextPrimary)
            Spacer()
            if report.hasIssues {
                Text("\(report.errorCount) 个问题 · \(report.warningCount) 个建议")
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            } else {
                Text(String(localized: "redpacket.quality.allGood"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.green)
            }
        }
        .padding(.bottom)
    }

    // MARK: - 质量列表

    private func qualityList(report: RedPacketQualityReport) -> some View {
        VStack(spacing: 12) {
            ForEach(report.items) { item in
                qualityRow(item: item)
            }
        }
    }

    private func qualityRow(item: RedPacketQualityItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(levelColor(item.level))
                .frame(width: 10, height: 10)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dimensionName(item.dimension))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                    if item.level.needsAction {
                        Text(levelBadge(item.level))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(levelColor(item.level).opacity(0.2))
                            .foregroundStyle(levelColor(item.level))
                            .clipShape(Capsule())
                    }
                }
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
        }
    }

    // MARK: - 未检测

    private var notEvaluatedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 40))
                .foregroundStyle(Color.milensTextSecondary)
            Text(String(localized: "redpacket.quality.notEvaluated"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
            Button {
                viewModel.evaluateQuality()
            } label: {
                Text(String(localized: "redpacket.quality.startCheck"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.milensActionPrimary)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - 底部栏

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // 优化摘要
            if !viewModel.optimizationSummary.isEmpty {
                Text(String(localized: "redpacket.optimize.applied"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensActionPrimary)
            }

            // 智能优化按钮
            Button {
                viewModel.applySmartOptimization()
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text(String(localized: "redpacket.optimize.button"))
                }
                .font(.uiBodyStrong)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(viewModel.isOptimizing ? Color.milensActionPrimary.opacity(0.5) : Color.milensActionPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            }
            .disabled(viewModel.isOptimizing)

            Text(String(localized: "redpacket.optimize.disclaimer"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .padding()
    }

    // MARK: - 辅助

    private func levelColor(_ level: RedPacketQualityLevel) -> Color {
        switch level {
        case .pass: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func levelText(_ level: RedPacketQualityLevel) -> String {
        switch level {
        case .pass: return String(localized: "redpacket.quality.level.pass")
        case .warning: return String(localized: "redpacket.quality.level.warning")
        case .error: return String(localized: "redpacket.quality.level.error")
        }
    }

    private func levelBadge(_ level: RedPacketQualityLevel) -> String {
        switch level {
        case .pass: return ""
        case .warning: return String(localized: "redpacket.quality.badge.warning")
        case .error: return String(localized: "redpacket.quality.badge.error")
        }
    }

    private func dimensionName(_ dimension: RedPacketQualityDimension) -> String {
        switch dimension {
        case .clarity: return String(localized: "redpacket.quality.dim.clarity")
        case .brightness: return String(localized: "redpacket.quality.dim.brightness")
        case .composition: return String(localized: "redpacket.quality.dim.composition")
        case .cutout: return String(localized: "redpacket.quality.dim.cutout")
        case .readability: return String(localized: "redpacket.quality.dim.readability")
        }
    }
}
