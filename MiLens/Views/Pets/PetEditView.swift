//  PetEditView —— 宠物档案编辑（route .petEdit，对应源端 pages/PetEditPage.ets）。
//  PetEditViewModel（@Observable）驱动表单状态，校验/保存/未保存判定通过 PetFormLogic 纯函数。
//  P3 实现：名称/物种/性别/生日/领养日/备忘条目编辑 + 保存 + 删除 + 未保存确认。
//  特征注册：PhotosPicker 选 8–15 张 → PetMatcher 提取聚合写入 featureData（自动归属前置条件）。

import SwiftUI
import PhotosUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "PetEditView")

struct PetEditView: View {
    let petID: UUID

    @Environment(\.petRepository) private var petRepo
    @Environment(\.notifyService) private var notifyService
    @Environment(\.clipInferenceService) private var clipService
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PetEditViewModel?
    @State private var newNoteItem = ""
    @State private var showDeleteConfirm = false
    @State private var showBackConfirm = false
    /// 特征注册选中的照片（PhotosPicker 8–15 张）
    @State private var selectedFeatureItems: [PhotosPickerItem] = []
    /// 照片数据加载任务（loadTransferable，页面消失时取消）
    @State private var featureLoadTask: Task<Void, Never>?

    private let dateRange: ClosedRange<Date> = {
        let cal = Calendar(identifier: .gregorian)
        // 2000-01-01 在 Gregorian 日历必然有效；失败属于日历基础设施异常，显式崩溃并携带原因。
        guard let start = cal.date(from: DateComponents(year: 2000, month: 1, day: 1)) else {
            fatalError("无法构造 2000-01-01 日期（Gregorian 日历异常）")
        }
        return start...Date()
    }()

    var body: some View {
        Group {
            if let vm = viewModel {
                if vm.isLoading {
                    ProgressView()
                } else {
                    editForm(vm)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("编辑档案")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let vm = viewModel, !vm.isLoading {
                Button { save(vm) } label: {
                    Text("保存")
                        .font(.buttonLabel)
                        .foregroundStyle(Color.milensTextOnActionPrimary)
                        .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                        .background(Color.milensActionPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isSaving)
                .padding(.horizontal, Spacing.pagePad)
                .padding(.vertical, Spacing.sm)
            }
        }
        .task {
            if viewModel == nil {
                let vm = PetEditViewModel(petRepo: petRepo, clipService: clipService)
                vm.loadPet(id: petID)
                viewModel = vm
            }
        }
        .onDisappear {
            featureLoadTask?.cancel()
        }
        .alert("删除伙伴档案", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deletePet() }
        } message: {
            if let vm = viewModel {
                Text("确定删除「\(vm.form.name)」吗？\n关联照片将解除归属但不会删除。")
            }
        }
        .alert("有未保存的修改", isPresented: $showBackConfirm) {
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .interactiveDismissDisabled(viewModel?.hasUnsavedChanges ?? false)
    }

    // MARK: - 编辑表单

    private func editForm(_ vm: PetEditViewModel) -> some View {
        @Bindable var bindable = vm

        return Form {
            // 头像预览
            avatarSection(vm)

            // 基本信息
            Section("基本信息") {
                TextField("名字", text: $bindable.form.name)
                    .font(.bodyPrimary)
            }

            // 物种与性别
            Section("物种与性别") {
                Picker("物种", selection: $bindable.form.species) {
                    ForEach(Species.allCases, id: \.self) { s in
                        Text("\(PetProfileLogic.speciesEmoji(s)) \(PetDisplayLogic.speciesDisplayName(s))")
                            .tag(s)
                    }
                }
                Picker("性别", selection: $bindable.form.gender) {
                    ForEach(Gender.allCases, id: \.self) { g in
                        Text(PetDisplayLogic.genderDisplayName(g)).tag(g)
                    }
                }
            }

            // 重要日期
            dateSection(vm)

            // 视觉特征（自动归属前置条件）
            featureSection(vm)

            // 备忘
            notesSection(vm)

            // 错误提示
            if !vm.errorMessage.isEmpty {
                Section {
                    Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.milensDanger)
                        .font(.caption)
                }
            }

            // 删除
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除伙伴档案", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.milensGrouped)
        .background(Color.milensBackground)
    }

    // MARK: - 头像区

    private func avatarSection(_ vm: PetEditViewModel) -> some View {
        Section {
            HStack(spacing: Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.milensAccentSoft)
                        .frame(width: 64, height: 64)
                    // 无头像时用物种 Emoji 占位（头像选择后置 V1.x）
                    Text(PetProfileLogic.speciesEmoji(vm.form.species))
                        .font(.system(size: 32))
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(vm.form.name.isEmpty ? "未命名" : vm.form.name)
                        .font(.titleStandard)
                    Text(PetDisplayLogic.speciesDisplayName(vm.form.species))
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.xs)
        } header: {
            Text("头像")
        } footer: {
            Text("头像选择功能将在后续版本支持")
                .font(.caption)
        }
    }

    // MARK: - 视觉特征区（对应源端 PetEditPage 注册区块）

    private func featureSection(_ vm: PetEditViewModel) -> some View {
        Section {
            if vm.featureRegistered {
                Label("已注册视觉特征", systemImage: "checkmark.circle.fill")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensPrimary)
            }

            if vm.isRegisteringFeatures {
                HStack(spacing: Spacing.md) {
                    ProgressView()
                    Text("正在提取特征 \(vm.featureRegistrationProgress)/\(selectedFeatureItems.count)")
                        .font(.bodyPrimary)
                }
                Button("取消") { vm.cancelFeatureRegistration() }
                    .font(.caption)
            } else {
                // PhotosPicker 的 label 闭包是 Sendable：先取出局部值，不在闭包内读 MainActor 隔离属性
                let isRegistered = vm.featureRegistered
                PhotosPicker(
                    selection: $selectedFeatureItems,
                    maxSelectionCount: PetFormConstants.maxRegistrationPhotos,
                    matching: .images
                ) {
                    Label(isRegistered ? "重新注册（更新特征）" : "选择照片注册",
                          systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(clipService == nil)

                if clipService == nil {
                    Text("AI 模型未就绪，暂不能注册视觉特征")
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                }

                if !selectedFeatureItems.isEmpty {
                    Text("已选 \(selectedFeatureItems.count) 张")
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                    Button {
                        loadAndRegister(vm)
                    } label: {
                        Text("开始注册")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedFeatureItems.count < PetFormConstants.minRegistrationPhotos)
                }
            }

            if !vm.featureRegistrationMessage.isEmpty {
                Text(vm.featureRegistrationMessage)
                    .font(.caption)
                    .foregroundStyle(vm.featureRegistered ? Color.milensTextSecondary : Color.milensDanger)
            }
        } header: {
            Text("视觉特征")
        } footer: {
            Text(vm.featureRegistered
                 ? "更新特征需要重新选择照片（\(PetFormConstants.minRegistrationPhotos)–\(PetFormConstants.maxRegistrationPhotos) 张）"
                 : "选择 \(PetFormConstants.minRegistrationPhotos)–\(PetFormConstants.maxRegistrationPhotos) 张不同角度与光线的照片，导入新照片时将自动归入此档案")
                .font(.caption)
        }
    }

    /// 加载选中的照片数据后触发注册（加载失败的照片自动跳过）。
    private func loadAndRegister(_ vm: PetEditViewModel) {
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
                vm.registerFeature(imageDatas: datas)
            }
        }
    }

    // MARK: - 日期区

    private func dateSection(_ vm: PetEditViewModel) -> some View {
        @Bindable var bindable = vm

        return Section("重要日期") {
            DatePicker(
                "生日",
                selection: Binding(
                    get: { vm.form.birthday ?? Date() },
                    set: { vm.updateBirthday($0) }
                ),
                in: dateRange,
                displayedComponents: .date
            )
            .environment(\.locale, Locale(identifier: "zh_CN"))

            DatePicker(
                "领养日",
                selection: Binding(
                    get: { vm.form.adoptionDay ?? Date() },
                    set: { vm.updateAdoptionDay($0) }
                ),
                in: dateRange,
                displayedComponents: .date
            )
            .environment(\.locale, Locale(identifier: "zh_CN"))

            // 清除日期
            if vm.form.birthday != nil || vm.form.adoptionDay != nil {
                Button("清除日期", role: .destructive) {
                    vm.updateBirthday(nil)
                    vm.updateAdoptionDay(nil)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - 备忘区

    private func notesSection(_ vm: PetEditViewModel) -> some View {
        @Bindable var bindable = vm

        return Section {
            // 已有备忘条目
            ForEach(Array(bindable.form.noteItems.enumerated()), id: \.offset) { index, note in
                HStack {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Color.milensPrimary)
                    Text(note)
                        .font(.bodyPrimary)
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        vm.removeNoteItem(at: index)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }

            // 新增备忘输入
            HStack {
                TextField("添加重要事件（可选）", text: $newNoteItem)
                    .font(.bodyPrimary)
                    .onSubmit { addNote(vm) }
                Button {
                    addNote(vm)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.milensPrimary)
                }
                .disabled(newNoteItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("重要事件")
        } footer: {
            Text("每条不超过 \(PetFormConstants.maxNoteItemLength) 字")
                .font(.caption)
        }
    }

    // MARK: - 操作

    private func addNote(_ vm: PetEditViewModel) {
        let ok = vm.addNoteItem(newNoteItem)
        if ok {
            newNoteItem = ""
        }
    }

    private func save(_ vm: PetEditViewModel) {
        if vm.save() {
            // 生日/领养日可能变更：局部重调度该宠物的纪念提醒
            if let notifyService {
                do {
                    if let pet = try petRepo.getPet(id: petID) {
                        Task { await notifyService.updateReminders(for: pet) }
                    }
                } catch {
                    logger.error("save: 读取宠物失败（\(self.petID)，\(error.localizedDescription)）")
                }
            }
            dismiss()
        }
    }

    private func deletePet() {
        let pet: Pet?
        do {
            pet = try petRepo.getPet(id: petID)
        } catch {
            pet = nil
            logger.error("deletePet: 读取档案失败（\(self.petID)，\(error.localizedDescription)）")
        }
        if let pet {
            do {
                try petRepo.deletePet(pet)
            } catch {
                logger.error("deletePet: 删除档案失败（\(self.petID)，\(error.localizedDescription)）")
            }
            // 撤销该宠物的纪念提醒
            if let notifyService {
                Task { await notifyService.removeReminders(for: pet) }
            }
        }
        dismiss()
    }
}
