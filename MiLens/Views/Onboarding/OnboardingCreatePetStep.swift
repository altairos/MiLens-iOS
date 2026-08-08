//  OnboardingCreatePetStep —— 首次启动 Step 4 建档页（UI-DESIGN.md §6.1）。
//  情绪峰值：记忆标记 + 扫描发现照片数 + 名字输入；创建动作由容器主按钮触发
//  （OnboardingViewModel.createFirstPet，PetProfileLogic 校验语义）。
//  建档成功后切换到特征注册引导卡片（PhotosPicker 8–15 张 → PetMatcher 注册，
//  自动归属前置条件；「稍后再说」可跳过）。
//  视觉：图标中性细线；文楷标题每屏唯一；输入框底色 SurfaceGrouped + 0.5pt 描边；
//  主操作为 ActionPrimary 胶囊（文字走 TextOnActionPrimary 保证对比度，§3.1）。

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
            Spacer(minLength: Spacing.xxl)

            // 情绪峰值区（本屏唯一文楷；计数用记忆标记 + 圆体数字）
            VStack(spacing: Spacing.md) {
                Image(systemName: "pawprint")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.milensTextSecondary)
                if viewModel.scanFoundCount > 0 {
                    Text("我们找到了它")
                        .font(.displayMedium)
                        .foregroundStyle(Color.milensTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: Spacing.sm) {
                        Circle()
                            .fill(Color.milensPrimary)
                            .frame(width: 6, height: 6)
                        Text("照片：\(viewModel.scanFoundCount) 张")
                            .font(.numberStat)
                            .foregroundStyle(Color.milensTextPrimary)
                    }
                } else {
                    Text("为它创建第一份档案")
                        .font(.displayMedium)
                        .foregroundStyle(Color.milensTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("随时可以在相册页扫描并导入更多照片")
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }

            // 名字输入
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("它叫什么名字？")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                TextField("输入宠物名字", text: $viewModel.petName)
                    .font(.bodyPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(Color.milensGrouped)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .stroke(Color.milensBorder, lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .submitLabel(.done)
                    .onSubmit { viewModel.submitCreatePet() }
            }
            .padding(.horizontal, Spacing.pagePad)

            // 校验错误
            if !viewModel.scanError.isEmpty {
                Label(viewModel.scanError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.milensDanger)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.pagePad)
    }

    // MARK: - 特征注册引导卡片

    private var featureRegistrationCard: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: Spacing.xxl)

            VStack(spacing: Spacing.md) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.milensTextSecondary)
                Text("档案已创建")
                    .font(.displayMedium)
                    .foregroundStyle(Color.milensTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("选择 8–15 张不同角度的照片，注册「\(viewModel.petName)」的视觉特征。\n以后导入的新照片将自动归入此档案。")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.lg)

            // 注册状态区
            if viewModel.featureRegistered {
                Label("已注册视觉特征", systemImage: "checkmark.circle.fill")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensSuccess)
            } else if viewModel.isRegisteringFeatures {
                HStack(spacing: Spacing.md) {
                    ProgressView()
                        .tint(Color.milensTextSecondary)
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
                        .foregroundStyle(Color.milensTextPrimary)
                        .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                        .background(Color.milensGrouped)
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                                .stroke(Color.milensBorder, lineWidth: 0.5)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
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
                            .foregroundStyle(Color.milensTextOnActionPrimary)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.milensActionPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedFeatureItems.count < PetFormConstants.minRegistrationPhotos)
                    .opacity(selectedFeatureItems.count < PetFormConstants.minRegistrationPhotos ? 0.5 : 1)
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
                        .foregroundStyle(Color.milensTextOnActionPrimary)
                        .frame(maxWidth: .infinity, minHeight: 50)
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
                .frame(minHeight: Sizing.touchTarget)
                .contentShape(Rectangle())
            } else {
                Button("稍后再说") {
                    viewModel.skipFeatureRegistration()
                }
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
                .frame(minHeight: Sizing.touchTarget)
                .contentShape(Rectangle())
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.pagePad)
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
