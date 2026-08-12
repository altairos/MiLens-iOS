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
                    overline: "FEATURE REGISTER · 8—15 张",
                    title: "用 8–15 张照片，\n建立特征基准",
                    body: "选择清晰、角度不同、只包含\(viewModel.petName)的照片；\n所有处理都在本机完成。",
                    trailing: AnyView(
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(loadedImageDatas.count)")
                                .font(.system(size: 28, weight: .bold, design: .default))
                                .foregroundStyle(Color.milensActionPrimary)
                            Text("/ \(PetFormConstants.maxRegistrationPhotos)")
                                .font(.system(size: 12))
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
                        Text(loadedImageDatas.isEmpty ? "选择 8–15 张照片"
                             : "重新选择（已选 \(loadedImageDatas.count) 张）")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.milensActionPrimary)
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.milensActionPrimary, lineWidth: 1)
                                .frame(width: 42, height: 32)
                            Text("\u{2192}")
                                .font(.system(size: 20))
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
                        label: "建立特征基准",
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
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.milensActionPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("特征基准")
                                .font(.system(size: 12))
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
                guidanceRow(number: "01", title: "清晰可见", subtitle: "避免严重模糊或遮挡", isLast: false)
                guidanceRow(number: "02", title: "角度有变化", subtitle: "正面、侧面与全身照", isLast: false)
                guidanceRow(number: "03", title: "只包含\(viewModel.petName)", subtitle: "减少其他动物干扰", isLast: true)
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
                    .font(.system(size: 12))
                    .foregroundStyle(Color.milensActionPrimary)
                    .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
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
                Text("\(loadedImageDatas.count) 张已准备好")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.milensActionPrimary)
                Text("只用来建立\(viewModel.petName)的本机特征基准。")
                    .font(.system(size: 12))
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
                    overline: "FEATURE REGISTER · 本机处理",
                    title: "正在本机建立\n\(viewModel.petName)的特征基准",
                    body: "将 \(loadedImageDatas.count) 张照片汇总为比较基准；\n不会上传，也不会在此时扫描图库。"
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
                    label: "正在建立基准…",
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
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .padding(.top, 22)

                Text("正在汇总特征基准")
                    .font(.system(size: 12))
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
                stageRow(title: "检查照片质量", status: pct > 0.33 ? "已完成" : "进行中",
                         isActive: pct <= 0.33, isLast: false)
                stageRow(title: "提取本机特征", status: pct > 0.66 ? "已完成" : (pct > 0.33 ? "进行中" : "稍后"),
                         isActive: pct > 0.33 && pct <= 0.66, isLast: false)
                stageRow(title: "汇总为\(viewModel.petName)的基准", status: pct >= 1 ? "已完成" : (pct > 0.66 ? "进行中" : "稍后"),
                         isActive: pct > 0.66, isLast: true)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
    }

    private func stageRow(title: String, status: String, isActive: Bool, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(status == "已完成" ? Color.milensActionPrimary
                          : (isActive ? Color.milensPrimary : Color.milensSeparator))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(status == "已完成" ? Color.milensActionPrimary
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
                    overline: "FEATURE REGISTER · 已建立",
                    title: "\(viewModel.petName)的特征基准，\n已经建立",
                    body: "现在「咪Lens」有了进行相似度比较的基准；\n候选仍不等于确定识别。"
                )

                // Feature Seal 卡片
                featureSealCard
                    .padding(.top, Spacing.xxl)

                // Next Full Library Access 卡片
                nextFullLibraryCard
                    .padding(.top, Spacing.lg)

                // ContactProofButton「允许扫描系统图库」
                ContactProofButton(label: "允许扫描系统图库") {
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
                    Text("FEATURE BASELINE")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.milensTextSecondary)
                    Text(viewModel.petName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.milensTextPrimary)
                    Text("\(loadedImageDatas.count) 张注册照片")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.milensTextPrimary)
                    Text("仅保存在本机")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.milensTextSecondary)
                    HStack {
                        Spacer()
                        // ✓ 印章
                        ZStack {
                            Circle()
                                .fill(Color.milensActionPrimary)
                                .frame(width: 44, height: 44)
                            Text("\u{2713}")
                                .font(.system(size: 20, weight: .bold))
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
                Text("下一步：全面扫描系统图库")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.milensTextPrimary)
                Text("需要在系统面板允许访问全部照片。\n扫描只会生成候选，不会自动导入。")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.milensTextSecondary)
                Text("你仍可随时停止扫描或撤回权限。")
                    .font(.system(size: 12))
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
