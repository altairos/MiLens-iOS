//  OnboardingImportStep —— 首次启动 04 导入中 / 导入成功（对照 Figma #123:161 / #123:198）。
//  按 viewModel.step 分支：
//  - importing（#123:161）：Lens 卡片（百分比 + 正在写入）+ Progress Track + Stages 卡片。
//    ContactProofButton disabled。
//  - success（#123:198）：Archive Entry Card（归档照片 + Paper 区 + Timeline 进度条）+
//    Local Archive Proof 卡片（本地隐私证明）+ 底部说明。
//    ContactProofButton"开启「名字」的生命档案"（→ finish）。

import SwiftUI

struct OnboardingImportStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        Group {
            switch viewModel.step {
            case .importing:
                importingView
            case .success:
                successView
            default:
                EmptyView()
            }
        }
    }

    // MARK: - importing（#123:161 导入中）

    private var importingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialSection(
                    overline: viewModel.stepOverline,
                    title: String(localized: "onboarding.import.title \(viewModel.petName)"),
                    bodyText: String(localized: "onboarding.import.body \(viewModel.selectedCandidateIDs.count)")
                )

                lensCard
                    .padding(.top, Spacing.xxl)

                progressTrack
                    .padding(.top, Spacing.lg)

                stagesCard
                    .padding(.top, Spacing.lg)

                ContactProofButton(label: String(localized: "onboarding.import.writing \(viewModel.selectedCandidateIDs.count)"),
                                   isEnabled: false) {}
                    .padding(.top, Spacing.xxl)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    private var lensCard: some View {
        EditorialCard(cornerRadius: Radius.large) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(Color.milensBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .frame(width: 164, height: 164)
                    Circle()
                        .fill(Color.milensGrouped)
                        .frame(width: 116, height: 116)
                    Circle()
                        .fill(Color.milensPrimary)
                        .frame(width: 12, height: 12)
                        .offset(x: 0, y: -76)
                    Text("\(Int(viewModel.importPercent * 100))%")
                        .font(.numberStat)
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .padding(.top, 22)

                Text(String(localized: "onboarding.import.lens.title"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.bottom, 22)
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
        }
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.milensSeparator)
                    .frame(height: 6)
                    .clipShape(Capsule())
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: geo.size.width * viewModel.importPercent, height: 6)
                    .clipShape(Capsule())
            }
        }
        .frame(height: 6)
    }

    private var stagesCard: some View {
        EditorialCard(cornerRadius: Radius.medium) {
            VStack(alignment: .leading, spacing: 0) {
                let pct = viewModel.importPercent
                // 三态 status 与 stageRow 共用 onboarding.status.* key（同 locale 解析相等）
                let doneText = String(localized: "onboarding.status.done")
                let inProgressText = String(localized: "onboarding.status.inProgress")
                let laterText = String(localized: "onboarding.status.later")
                stageRow(title: String(localized: "onboarding.import.stage.copy"),
                         status: pct > 0.33 ? doneText : inProgressText,
                         isActive: pct <= 0.33, isLast: false)
                stageRow(title: String(localized: "onboarding.import.stage.archive \(viewModel.petName)"),
                         status: pct > 0.66 ? doneText : (pct > 0.33 ? inProgressText : laterText),
                         isActive: pct > 0.33 && pct <= 0.66, isLast: false)
                stageRow(title: String(localized: "onboarding.import.stage.thumbnails"),
                         status: pct >= 1 ? doneText : (pct > 0.66 ? inProgressText : laterText),
                         isActive: pct > 0.66, isLast: true)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
    }

    private func stageRow(title: String, status: String, isActive: Bool, isLast: Bool) -> some View {
        // status 与调用方共用同一 onboarding.status.done key：同 locale 下解析结果
        // 相等，保留字符串比较即可判定“已完成”看色。
        let isDone = status == String(localized: "onboarding.status.done")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isDone ? Color.milensActionPrimary
                          : (isActive ? Color.milensPrimary : Color.milensSeparator))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text(status)
                    .font(.editorialMetadata)
                    .foregroundStyle(isDone ? Color.milensActionPrimary
                                     : (isActive ? Color.milensActionPrimary : Color.milensTextSecondary))
            }
            .padding(.vertical, 14)
            if !isLast {
                Rectangle().fill(Color.milensSeparator).frame(height: 1)
            }
        }
    }

    // MARK: - success（#123:198 导入成功）

    private var successView: some View {
        ScrollView {
            VStack(spacing: 0) {
                archiveEntryCard
                localArchiveProof
                    .padding(.top, 24)
                backupKeepCard
                    .padding(.top, 16)
                privacyNote
                    .padding(.top, 16)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, 80)
            .padding(.top, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            ContactProofButton(label: String(localized: "onboarding.import.cta \(viewModel.petName)")) {
                viewModel.finishAfterImport()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
            .background(Color.milensBackground)
        }
    }

    // MARK: - Archive Entry Card（对照 #123:198）

    private var archiveEntryCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Color.milensGrouped)
                    .frame(height: 224)

                Rectangle()
                    .fill(Color.milensInk.opacity(0.36))
                    .frame(height: 78)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                Text("\(viewModel.petName) · \(Date(), format: .dateTime.year().month())")
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensDarkroomText)
                    .padding(.leading, 18)
                    .padding(.bottom, 16)
            }
            .frame(height: 224)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(localized: "onboarding.import.longArchiveMark"))
                            .font(.editorialOverline)
                            .tracking(0.1)
                            .foregroundStyle(Color.milensActionPrimary)
                            .padding(.top, 18)

                        Text(String(localized: "onboarding.import.count \(viewModel.importedCount)"))
                            .font(.editorialSection)
                            .foregroundStyle(Color.milensTextPrimary)
                            .padding(.top, 8)

                        Text(String(localized: "onboarding.import.memoryTitle \(viewModel.petName)"))
                            .font(.bodySecondary)
                            .foregroundStyle(Color.milensTextSecondary)
                            .padding(.top, 4)

                        timelineBar
                            .padding(.top, 16)
                            .padding(.bottom, 22)
                    }
                    .padding(.leading, 13)
                    .padding(.trailing, 16)
                }
            }
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var timelineBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: geo.size.width * 0.92, height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
        .frame(height: 10)
    }

    // MARK: - Local Archive Proof（对照 #123:198）

    private var localArchiveProof: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "onboarding.import.localMark"))
                    .font(.editorialOverline)
                    .tracking(0.1)
                    .foregroundStyle(Color.milensActionPrimary)
                    .padding(.top, 16)

                Text(String(localized: "onboarding.import.local.title"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, 8)

                Text(String(localized: "onboarding.import.local.body"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, 2)

                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 1)
                    .padding(.top, 16)

                HStack(spacing: 0) {
                    statColumn(value: String(format: "%02d", viewModel.importedCount), label: String(localized: "onboarding.import.stat.originals"))
                    Spacer()
                    statColumn(value: String(format: "%02d", viewModel.importedCount), label: String(localized: "onboarding.import.stat.thumbnails"))
                    Spacer()
                    statColumn(value: "01", label: String(localized: "onboarding.import.stat.pets"))
                }
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .padding(.leading, 13)
            .padding(.trailing, 16)
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.custom("Fraunces-Bold", size: 12))
                .foregroundStyle(Color.milensTextPrimary)
            Text(label)
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.top, 4)
        }
    }

    // MARK: - 备份留存引导卡片（导入成功后种下认知）

    /// 情感化备份引导：强调记忆的珍贵与完整保存，不使用「换机丢失」这类表述
    /// （产品定位是记忆本身的安全感，而非对设备风险的恐惧）。
    /// 纯展示卡片——Onboarding 完成后才进主界面，进入后首页横幅会再次引导。
    private var backupKeepCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.timemachine")
                        .font(.system(size: Sizing.iconSm))
                        .foregroundStyle(Color.milensActionPrimary)
                    Text(String(localized: "onboarding.import.memoryMark"))
                        .font(.editorialOverline)
                        .tracking(0.1)
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .padding(.top, 16)

                Text(String(localized: "onboarding.import.keep.title"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, 8)

                Text(String(localized: "onboarding.import.keep.body"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)
            }
            .padding(.leading, 13)
            .padding(.trailing, 16)
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 隐私说明

    private var privacyNote: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 196, height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            Text(String(localized: "onboarding.import.note"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
