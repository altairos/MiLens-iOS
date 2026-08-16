//  OnboardingFullScanStep —— 首次启动 04 全面扫描系统图库（对照 Figma #47:9）。
//  EditorialSection（LOCAL SCAN · 特征基准已就绪 + "正在全面扫描系统图库"）+
//  Viewfinder 卡片（照片底 + 扫描线 + 十字线 + Status 行"本机扫描·正在比较 N/M"）+
//  Candidate Ledger 卡片（当前相似候选 N 张）+ Stages 卡片。
//  ContactProofButton disabled"正在全面扫描…"（扫描中）；完成后自动进 candidates。
//  扫描错误 / 无候选 / 跳过扫描的降级路径。

import SwiftUI

struct OnboardingFullScanStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialSection(
                    overline: viewModel.stepOverline,
                    title: viewModel.isScanning ? String(localized: "onboarding.scan.title") : scanCompleteTitle,
                    bodyText: viewModel.isScanning
                        ? String(localized: "onboarding.scan.body \(viewModel.petName)")
                        : scanCompleteBody
                )

                // Viewfinder 卡片（扫描中显示扫描线动画）
                viewfinderCard
                    .padding(.top, Spacing.xxl)

                // Candidate Ledger 卡片
                if viewModel.scanFoundCount > 0 || viewModel.scanCompleted {
                    candidateLedgerCard
                        .padding(.top, Spacing.lg)
                }

                // Stages 卡片
                stagesCard
                    .padding(.top, Spacing.lg)

                // 扫描错误
                if !viewModel.scanError.isEmpty {
                    Label(viewModel.scanError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.milensDanger)
                        .padding(.top, Spacing.md)
                }

                // 主操作
                if viewModel.isScanning {
                    ContactProofButton(label: String(localized: "onboarding.scan.scanning"), isEnabled: false) {}
                        .padding(.top, Spacing.xxl)
                } else if viewModel.scanCompleted && !viewModel.scanError.isEmpty {
                    // 失败：允许跳过
                    ContactProofButton(label: String(localized: "onboarding.scan.skip")) {
                        viewModel.skipScan()
                        viewModel.goToNextStep()
                    }
                    .padding(.top, Spacing.xxl)
                } else if viewModel.scanCompleted && viewModel.scanFoundCount > 0 {
                    ContactProofButton(label: String(localized: "onboarding.scan.viewCandidates \(viewModel.scanFoundCount)")) {
                        viewModel.goToNextStep()
                    }
                    .padding(.top, Spacing.xxl)
                } else {
                    // 无候选：直接完成
                    ContactProofButton(label: String(localized: "onboarding.scan.finish")) {
                        viewModel.finish()
                    }
                    .padding(.top, Spacing.xxl)
                }
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    private var scanCompleteTitle: String {
        if !viewModel.scanError.isEmpty { return String(localized: "onboarding.scan.incomplete") }
        return String(localized: "onboarding.scan.complete")
    }

    private var scanCompleteBody: String {
        if !viewModel.scanError.isEmpty {
            return String(localized: "onboarding.scan.incomplete.hint")
        }
        return viewModel.scanFoundCount > 0
            ? String(localized: "onboarding.scan.found \(viewModel.scanFoundCount) \(viewModel.petName)")
            : String(localized: "onboarding.scan.none \(viewModel.petName)")
    }

    // MARK: - Viewfinder 卡片（对照 #47:9 Scan / Viewfinder）

    private var viewfinderCard: some View {
        EditorialCard(cornerRadius: Radius.large) {
            ZStack {
                // 照片底（占位）
                Rectangle()
                    .fill(Color.milensGrouped)
                    .frame(height: 198)

                // 扫描线（仅扫描中显示；Reduce Motion 由 ScanLine 内部处理为静止顶线）
                if viewModel.isScanning {
                    ScanLine(color: Color.milensPrimary, horizontalInset: 22, bottomInset: 18)
                        .frame(height: 198)
                }

                // 十字线（对照 #47:9 Rule）
                Rectangle()
                    .fill(Color.milensPrimary)
                    .frame(width: 298, height: 2)
                    .opacity(0.6)
                Rectangle()
                    .fill(Color.milensPrimary)
                    .frame(width: 1, height: 154)
                    .opacity(0.6)
            }
            .frame(height: 198)
            .padding(.top, 0)

            // Status 行（对照 #47:9 Scan / Status）
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.milensPrimary)
                    .frame(width: 9, height: 9)
                Text(viewModel.isScanning
                     ? String(localized: "onboarding.scan.status.comparing")
                     : String(localized: "onboarding.scan.status.completed"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                if viewModel.isScanning && viewModel.scanTotal > 0 {
                    Text("\(viewModel.scanScanned) / \(viewModel.scanTotal)")
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.milensCard)
        }
    }

    // MARK: - Candidate Ledger 卡片（对照 #47:9 Scan / Candidate Ledger）

    private var candidateLedgerCard: some View {
        EditorialCard(cornerRadius: Radius.medium) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "onboarding.scan.candidates.title"))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(String(localized: "onboarding.scan.candidates.hint"))
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
                Spacer()
                Text("\(viewModel.scanFoundCount)")
                    .font(.numberStat)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "onboarding.scan.unit"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.leading, 2)
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Stages 卡片（对照 #47:9 Scan / Stages）

    private var stagesCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 2)
            HStack {
                Text(String(localized: "onboarding.scan.stage.thumbnails"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text(viewModel.isScanning
                     ? String(localized: "onboarding.status.inProgress")
                     : String(localized: "onboarding.status.done"))
                    .font(.bodySecondary)
                    .foregroundStyle(viewModel.isScanning ? Color.milensActionPrimary : Color.milensTextSecondary)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
        .background(Color.milensGrouped)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}
