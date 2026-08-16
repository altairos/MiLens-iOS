//  OnboardingFeatureRegisterStep —— 首次启动 03 特征注册（3 子状态共用文件）。
//  按 viewModel.step 分支渲染：
//  - featureIntro（#47:8/#47:11）：PhotosPicker 选图 + Guidance 卡片 + ContactProofButton/FocusDialButton
//  - featureProcessing（#117:50）：Lens 圆环 + 百分比 + Progress Track + Stages 卡片
//  - featureDone（#117:100）：Feature Seal 卡片 + Next Full Library Access 卡片
//  选图复用 PhotosPicker + loadTransferable（与 PetEditView 同一链路）；
//  注册由 OnboardingViewModel.registerCreatedPetFeature 编排 PetMatcher。

import SwiftUI
import PhotosUI

struct OnboardingFeatureRegisterStep: View {
    @Bindable var viewModel: OnboardingViewModel

    /// 特征注册选中的照片（PhotosPicker 8–15 张）
    @State private var selectedFeatureItems: [PhotosPickerItem] = []
    /// 照片数据加载任务（loadTransferable，视图消失时取消）
    @State private var featureLoadTask: Task<Void, Never>?
    /// 已加载的照片数据（用于注册）
    @State private var loadedImageDatas: [Data] = []

    var body: some View {
        Group {
            switch viewModel.step {
            case .featureIntro:
                featureIntroView
            case .featureProcessing:
                featureProcessingView
            case .featureDone:
                featureDoneView
            default:
                EmptyView()
            }
        }
        .onDisappear {
            featureLoadTask?.cancel()
        }
    }

    // MARK: - featureIntro（#47:8 说明与选图 / #47:11 已选 N 张）

    private var featureIntroView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialSection(
                    overline: viewModel.stepOverline,
                    title: String(localized: "onboarding.feature.intro.title"),
                    bodyText: String(localized: "onboarding.feature.intro.body \(viewModel.petName)"),
                    trailing: AnyView(
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(loadedImageDatas.count)")
                                .font(.numberStat)
                                .foregroundStyle(Color.milensActionPrimary)
                            Text("/ \(PetFormConstants.maxRegistrationPhotos)")
                                .font(.bodySecondary)
                                .foregroundStyle(Color.milensTextSecondary)
                        }
                    )
                )

                // Contact Sheet / Photo Grid 卡片
                contactSheetCard
                    .padding(.top, Spacing.xxl)

                // Guidance 卡片
                guidanceCard
                    .padding(.top, Spacing.lg)

                // Selected Photos 说明卡（选满下限后显示）
                if loadedImageDatas.count >= PetFormConstants.minRegistrationPhotos {
                    readyNoteCard
                        .padding(.top, Spacing.lg)
                }

                // 错误提示
                if !viewModel.featureRegistrationMessage.isEmpty,
                   !viewModel.featureRegistered {
                    Label(viewModel.featureRegistrationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.milensDanger)
                        .padding(.top, Spacing.md)
                }

                // PhotosPicker（ContactProofButton 样式触发选图）
                PhotosPicker(selection: $selectedFeatureItems,
                             maxSelectionCount: PetFormConstants.maxRegistrationPhotos,
                             matching: .images) {
                    HStack {
                        Text(loadedImageDatas.isEmpty
                             ? String(localized: "onboarding.feature.select")
                             : String(localized: "onboarding.feature.reselect \(loadedImageDatas.count)"))
                            .font(.buttonLabel)
                            .foregroundStyle(Color.milensActionPrimary)
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.milensActionPrimary, lineWidth: 1)
                                .frame(width: 42, height: 32)
                            Text("\u{2192}")
                                .font(.system(size: 20)) // ui-token:ok 装饰箭头字符
                                .foregroundStyle(Color.milensActionPrimary)
                        }
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 5)
                    .frame(height: 54)
                    .background(Color.milensAccentWash)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, Spacing.xxl)

                // Focus Dial（选满下限后显示）
                if loadedImageDatas.count >= PetFormConstants.minRegistrationPhotos {
                    FocusDialButton(
                        label: String(localized: "onboarding.feature.cta"),
                        systemImage: "checkmark"
                    ) {
                        startRegistration()
                    }
                    .padding(.top, Spacing.md)
                }
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .onChange(of: selectedFeatureItems) { _, items in
            loadImageData(from: items)
        }
    }

    // MARK: - Contact Sheet 卡片（对照 #47:8 / #47:11）

    private var contactSheetCard: some View {
        EditorialCard(cornerRadius: Radius.large) {
            VStack(alignment: .leading, spacing: 0) {
                if loadedImageDatas.isEmpty {
                    // 空态：5 个 sample 占位 + 数字 8
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.milensGrouped)
                                .frame(width: 50, height: 74)
                        }
                    }
                    .padding(.top, 24)
                    .padding(.leading, 22)

                    HStack {
                        Text("\(PetFormConstants.minRegistrationPhotos)")
                            .font(.numberStat)
                            .foregroundStyle(Color.milensActionPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(String(localized: "onboarding.feature.badge"))
                                .font(.bodySecondary)
                                .foregroundStyle(Color.milensTextSecondary)
                            Rectangle()
                                .fill(Color.milensActionPrimary)
                                .frame(width: 116, height: 2)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                } else {
                    // 已选照片网格
                    photoGrid
                        .padding(14)
                }
            }
        }
    }

    private var photoGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(loadedImageDatas.enumerated()), id: \.offset) { _, data in
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 76)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    // MARK: - Guidance 卡片（对照 #47:8 Registration / Guidance）

    private var guidanceCard: some View {
        EditorialCard(cornerRadius: Radius.medium) {
            VStack(alignment: .leading, spacing: 0) {
                guidanceRow(number: "01",
                            title: String(localized: "onboarding.feature.guidance.clarity"),
                            subtitle: String(localized: "onboarding.feature.guidance.clarity.detail"), isLast: false)
                guidanceRow(number: "02",
                            title: String(localized: "onboarding.feature.guidance.angle"),
                            subtitle: String(localized: "onboarding.feature.guidance.angle.detail"), isLast: false)
                guidanceRow(number: "03",
                            title: String(localized: "onboarding.feature.guidance.single \(viewModel.petName)"),
                            subtitle: String(localized: "onboarding.feature.guidance.single.detail"), isLast: true)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
    }

    private func guidanceRow(number: String, title: String, subtitle: String, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Text(number)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensActionPrimary)
                    .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(subtitle)
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            if !isLast {
                Rectangle().fill(Color.milensSeparator).frame(height: 1)
            }
        }
    }

    // MARK: - Ready Note 卡片（对照 #47:11 Registration / Ready Note）

    private var readyNoteCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "onboarding.feature.ready \(loadedImageDatas.count)"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "onboarding.feature.ready.note \(viewModel.petName)"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(.leading, 14)
            .padding(.vertical, 14)
            .padding(.trailing, 16)
            Spacer()
        }
        .background(Color.milensAccentWash)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    // MARK: - featureProcessing（#117:50 本机处理）

    private var featureProcessingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialSection(
                    overline: viewModel.stepOverline,
                    title: String(localized: "onboarding.feature.processing.title \(viewModel.petName)"),
                    bodyText: String(localized: "onboarding.feature.processing.body \(loadedImageDatas.count)")
                )

                // Lens 卡片（虚线轨道圆 + 百分比）
                lensCard
                    .padding(.top, Spacing.xxl)

                // Progress Track
                progressTrack
                    .padding(.top, Spacing.lg)

                // Stages 卡片
                stagesCard
                    .padding(.top, Spacing.lg)

                // Focus Dial disabled
                FocusDialButton(
                    label: String(localized: "onboarding.feature.processing.cta"),
                    systemImage: "ellipsis",
                    isEnabled: false
                ) {}
                .padding(.top, Spacing.xxl)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Lens 卡片（对照 #117:50 Registration / Lens）

    private var lensCard: some View {
        EditorialCard(cornerRadius: Radius.large) {
            VStack(spacing: 0) {
                ZStack {
                    // 虚线轨道圆
                    Circle()
                        .stroke(Color.milensBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .frame(width: 164, height: 164)
                    // portrait 占位（Grouped 色）
                    Circle()
                        .fill(Color.milensGrouped)
                        .frame(width: 116, height: 116)
                    // 进度圆点
                    Circle()
                        .fill(Color.milensPrimary)
                        .frame(width: 12, height: 12)
                        .offset(x: 0, y: -76)
                    // 百分比数字
                    Text("\(Int(viewModel.featureRegisterPercent * 100))%")
                        .font(.numberStat)
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .padding(.top, 22)

                Text(String(localized: "onboarding.feature.processing.status"))
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
                    .frame(width: geo.size.width * viewModel.featureRegisterPercent, height: 6)
                    .clipShape(Capsule())
            }
        }
        .frame(height: 6)
    }

    // MARK: - Stages 卡片（对照 #117:50 Registration / Stages）

    private var stagesCard: some View {
        EditorialCard(cornerRadius: Radius.medium) {
            VStack(alignment: .leading, spacing: 0) {
                let pct = viewModel.featureRegisterPercent
                stageRow(title: String(localized: "onboarding.feature.stage.quality"),
                         status: pct > 0.33 ? String(localized: "onboarding.status.done") : String(localized: "onboarding.status.inProgress"),
                         isActive: pct <= 0.33, isLast: false)
                stageRow(title: String(localized: "onboarding.feature.stage.extract"),
                         status: pct > 0.66 ? String(localized: "onboarding.status.done") : (pct > 0.33 ? String(localized: "onboarding.status.inProgress") : String(localized: "onboarding.status.later")),
                         isActive: pct > 0.33 && pct <= 0.66, isLast: false)
                stageRow(title: String(localized: "onboarding.feature.stage.summarize \(viewModel.petName)"),
                         status: pct >= 1 ? String(localized: "onboarding.status.done") : (pct > 0.66 ? String(localized: "onboarding.status.inProgress") : String(localized: "onboarding.status.later")),
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
        VStack(alignment: .leading, spacing: 0) {
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
                    .font(.bodySecondary)
                    .foregroundStyle(isDone ? Color.milensActionPrimary
                                     : (isActive ? Color.milensActionPrimary : Color.milensTextSecondary))
            }
            .padding(.vertical, 14)
            if !isLast {
                Rectangle().fill(Color.milensSeparator).frame(height: 1)
            }
        }
    }

    // MARK: - featureDone（#117:100 基准已建立）

    private var featureDoneView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialSection(
                    overline: viewModel.stepOverline,
                    title: String(localized: "onboarding.feature.done.title \(viewModel.petName)"),
                    bodyText: String(localized: "onboarding.feature.done.body")
                )

                // Feature Seal 卡片
                featureSealCard
                    .padding(.top, Spacing.xxl)

                // Next Full Library Access 卡片
                nextFullLibraryCard
                    .padding(.top, Spacing.lg)

                // ContactProofButton「允许扫描系统图库」
                ContactProofButton(label: String(localized: "onboarding.feature.done.cta")) {
                    viewModel.proceedToFullScan()
                }
                .padding(.top, Spacing.xxl)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Feature Seal 卡片（对照 #117:100 Archive / Feature Seal）

    private var featureSealCard: some View {
        EditorialCard(cornerRadius: Radius.large) {
            HStack(alignment: .top, spacing: 16) {
                // portrait 占位
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.milensGrouped)
                    .frame(width: 132, height: 166)

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "onboarding.feature.baseline"))
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                    Text(viewModel.petName)
                        .font(.uiTitle)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(String(localized: "onboarding.feature.done.count \(loadedImageDatas.count)"))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(String(localized: "onboarding.feature.done.localOnly"))
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                    HStack {
                        Spacer()
                        // ✓ 印章
                        ZStack {
                            Circle()
                                .fill(Color.milensActionPrimary)
                                .frame(width: 44, height: 44)
                            Text("\u{2713}")
                                .font(.system(size: 20, weight: .bold)) // ui-token:ok 印章装饰字符
                                .foregroundStyle(Color.milensTextOnActionPrimary)
                        }
                    }
                    .padding(.top, 8)
                }
                Spacer()
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
            .padding(.top, 20)
            .padding(.bottom, 20)

            // 底部分隔线
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(height: 2)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Next Full Library Access 卡片（对照 #117:100 Next）

    private var nextFullLibraryCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "onboarding.feature.done.next.title"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(String(localized: "onboarding.feature.done.next.body"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                Text(String(localized: "onboarding.feature.done.next.note"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, 4)
            }
            .padding(.leading, 18)
            .padding(.vertical, 16)
            .padding(.trailing, 16)
            Spacer()
        }
        .background(Color.milensGrouped)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    // MARK: - 加载照片数据

    private func loadImageData(from items: [PhotosPickerItem]) {
        featureLoadTask?.cancel()
        loadedImageDatas = []
        guard !items.isEmpty else { return }
        featureLoadTask = Task {
            var datas: [Data] = []
            for item in items {
                if Task.isCancelled { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    datas.append(data)
                }
            }
            await MainActor.run {
                self.loadedImageDatas = datas
            }
        }
    }

    private func startRegistration() {
        guard loadedImageDatas.count >= PetFormConstants.minRegistrationPhotos else { return }
        viewModel.registerCreatedPetFeature(imageDatas: loadedImageDatas)
    }
}
