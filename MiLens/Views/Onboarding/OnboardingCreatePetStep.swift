//  OnboardingCreatePetStep —— 首次启动 Step 4 建档页
//  （对应 iOS 设计稿「二、首次启动流程 Step 4」）。
//  情绪峰值：扫描发现照片数 + 名字输入；创建动作由容器主按钮触发
//  （OnboardingViewModel.createFirstPet，PetProfileLogic 校验语义）。
//  建档成功后切换到特征注册引导卡片（PhotosPicker 8–15 张 → PetMatcher 注册，
//  自动归属前置条件；「稍后再说」可跳过）。

import SwiftUI
import PhotosUI

struct OnboardingCreatePetStep: View {
    @Bindable var viewModel: OnboardingViewModel

    /// 特征注册选中的照片（PhotosPicker 8–15 张）
    @State private var selectedFeatureItems: [PhotosPickerItem] = []
    /// 照片数据加载任务（loadTransferable，视图消失时取消）
    @State private var featureLoadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if viewModel.showFeatureRegistration {
                featureRegistrationCard
            } else {
                createPetForm
            }
        }
        .onDisappear {
            featureLoadTask?.cancel()
        }
    }

    // MARK: - 建档表单

    private var createPetForm: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: 40)

            // 情绪峰值区（设计稿 Step 4：我们找到了小橘 / 照片：842 张）
            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.milensAccentSoft)
                        .frame(width: 96, height: 96)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.milensPrimary)
                }
                if viewModel.scanFoundCount > 0 {
                    Text("我们找到了它")
                        .font(.displayMedium)
                    Text("照片：\(viewModel.scanFoundCount) 张")
                        .font(.numberStat)
                        .foregroundStyle(Color.milensTextSecondary)
                } else {
                    Text("为它创建第一份档案")
                        .font(.displayMedium)
                    Text("随时可以在相册页扫描并导入更多照片")
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }

            // 名字输入
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("它叫什么名字？")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                TextField("输入宠物名字", text: $viewModel.petName)
                    .font(.bodyPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(Color.milensCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
                    .submitLabel(.done)
                    .onSubmit { viewModel.submitCreatePet() }
            }
            .padding(.horizontal, Spacing.xxl)

            // 校验错误
            if !viewModel.scanError.isEmpty {
                Label(viewModel.scanError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.milensDanger)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.xxl)
    }

    // MARK: - 特征注册引导卡片

    private var featureRegistrationCard: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: 40)

            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.milensAccentSoft)
                        .frame(width: 96, height: 96)
                    Image(systemName: "face.smiling")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.milensPrimary)
                }
                Text("档案已创建")
                    .font(.displayMedium)
                Text("选择 8–15 张不同角度的照片，注册「\(viewModel.petName)」的视觉特征。\n以后导入的新照片将自动归入此档案。")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.lg)

            // 注册状态区
            if viewModel.featureRegistered {
                Label("已注册视觉特征", systemImage: "checkmark.circle.fill")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensPrimary)
            } else if viewModel.isRegisteringFeatures {
                HStack(spacing: Spacing.md) {
                    ProgressView()
                    Text("正在提取特征 \(viewModel.featureRegistrationProgress)/\(selectedFeatureItems.count)")
                        .font(.bodyPrimary)
                }
            } else {
                PhotosPicker(
                    selection: $selectedFeatureItems,
                    maxSelectionCount: PetFormConstants.maxRegistrationPhotos,
                    matching: .images
                ) {
                    Label("选择照片注册", systemImage: "photo.on.rectangle")
                        .font(.bodyPrimary)
                        .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                        .background(Color.milensCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
                }

                if !selectedFeatureItems.isEmpty {
                    Text("已选 \(selectedFeatureItems.count) 张")
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                    Button {
                        loadAndRegister()
                    } label: {
                        Text("开始注册")
                            .font(.buttonLabel)
                            .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                            .background(Color.milensActionPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedFeatureItems.count < PetFormConstants.minRegistrationPhotos)
                }
            }

            // 结果/操作
            if !viewModel.featureRegistrationMessage.isEmpty {
                Text(viewModel.featureRegistrationMessage)
                    .font(.caption)
                    .foregroundStyle(viewModel.featureRegistered ? Color.milensTextSecondary : Color.milensDanger)
            }
            if viewModel.featureRegistered {
                Button {
                    viewModel.finishAfterFeatureRegistration()
                } label: {
                    Text("开始使用")
                        .font(.buttonLabel)
                        .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                        .background(Color.milensActionPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else if viewModel.isRegisteringFeatures {
                Button("取消") {
                    viewModel.skipFeatureRegistration()
                }
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
            } else {
                Button("稍后再说") {
                    viewModel.skipFeatureRegistration()
                }
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.xxl)
    }

    /// 加载选中的照片数据后触发注册（加载失败的照片自动跳过）。
    private func loadAndRegister() {
        let items = selectedFeatureItems
        guard !items.isEmpty else { return }
        featureLoadTask = Task {
            var datas: [Data] = []
            for item in items {
                if Task.isCancelled { break }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    datas.append(data)
                }
            }
            if !Task.isCancelled {
                viewModel.registerCreatedPetFeature(imageDatas: datas)
            }
        }
    }
}
