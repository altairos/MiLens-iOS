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

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.notifyService) private var notifyService
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PetEditViewModel?
    @State private var newNoteItem = ""
    @State private var showDeleteConfirm = false
    @State private var showBackConfirm = false
    /// 特征注册选中的照片（PhotosPicker 8–15 张）
    @State private var selectedFeatureItems: [PhotosPickerItem] = []
    /// 照片数据加载任务（loadTransferable，页面消失时取消）
    @State private var featureLoadTask: Task<Void, Never>?
    /// 头像选择：PhotosPicker 单选
    @State private var avatarPickerItem: PhotosPickerItem?
    /// 头像裁切 sheet
    @State private var showAvatarCropSheet = false
    /// 待裁切的头像原图（PhotosPicker 加载完成后设置）
    @State private var pendingAvatarImage: UIImage?

    private let dateRange: ClosedRange<Date> = Date.milensEpochStart...Date()

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
        .navigationTitle(String(localized: "pet.profile.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let vm = viewModel, !vm.isLoading {
                Button { save(vm) } label: {
                    Text(String(localized: "common.save"))
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
                let vm = factory.makePetEditViewModel()
                vm.loadPet(id: petID)
                viewModel = vm
            }
        }
        .onDisappear {
            featureLoadTask?.cancel()
        }
        .alert(String(localized: "pet.edit.delete.title"), isPresented: $showDeleteConfirm) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "common.delete"), role: .destructive) { deletePet() }
        } message: {
            if let vm = viewModel {
                Text(String(localized: "pet.edit.delete.message \(vm.form.name)"))
            }
        }
        .alert(String(localized: "pet.edit.unsaved.title"), isPresented: $showBackConfirm) {
            Button(String(localized: "pet.edit.unsaved.discard"), role: .destructive) { dismiss() }
            Button(String(localized: "pet.edit.unsaved.continue"), role: .cancel) {}
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
            Section(String(localized: "pet.edit.section.basic")) {
                TextField(String(localized: "pet.edit.name.placeholder"), text: $bindable.form.name)
                    .font(.bodyPrimary)
            }

            // 物种与性别
            Section(String(localized: "pet.edit.section.speciesGender")) {
                Picker(String(localized: "pet.edit.species"), selection: $bindable.form.species) {
                    ForEach(Species.allCases, id: \.self) { s in
                        Text("\(PetProfileLogic.speciesEmoji(s)) \(PetDisplayLogic.speciesDisplayName(s))")
                            .tag(s)
                    }
                }
                Picker(String(localized: "pet.edit.gender"), selection: $bindable.form.gender) {
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
                    Label(String(localized: "pet.edit.delete.title"), systemImage: "trash")
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
                    // 有头像显示头像，无头像用物种 Emoji 占位
                    if !vm.avatarPath.isEmpty,
                       let img = UIImage(contentsOfFile: vm.avatarPath) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                    } else {
                        Text(PetProfileLogic.speciesEmoji(vm.form.species))
                            .font(.system(size: 32)) // ui-token:ok 头像占位 emoji
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(vm.form.name.isEmpty ? String(localized: "pet.edit.name.unnamed") : vm.form.name)
                        .font(.titleStandard)
                    Text(PetDisplayLogic.speciesDisplayName(vm.form.species))
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                }
                Spacer()
                // 头像选择入口（PhotosPicker 单选）
                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                    Text(vm.avatarPath.isEmpty
                         ? String(localized: "pet.edit.avatar.choose")
                         : String(localized: "pet.edit.avatar.change"))
                        .font(.caption)
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .onChange(of: avatarPickerItem) { _, newItem in
                    loadAvatarImage(newItem)
                }
            }
            .padding(.vertical, Spacing.xs)
        } header: {
            Text(String(localized: "pet.edit.section.avatar"))
        } footer: {
            Text(String(localized: "pet.edit.avatar.footer"))
                .font(.caption)
        }
        .sheet(isPresented: $showAvatarCropSheet) {
            if let image = pendingAvatarImage {
                AvatarCropSheet(
                    image: image,
                    onCropped: { path in
                        vm.updateAvatarPath(path)
                        pendingAvatarImage = nil
                    },
                    onCancel: {
                        pendingAvatarImage = nil
                    }
                )
            }
        }
    }

    /// 加载 PhotosPicker 选中照片为 UIImage（后台解码，避免主线程卡顿）。
    private func loadAvatarImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    pendingAvatarImage = image
                    showAvatarCropSheet = true
                }
            }
            avatarPickerItem = nil
        }
    }

    // MARK: - 视觉特征区（对应源端 PetEditPage 注册区块）

    private func featureSection(_ vm: PetEditViewModel) -> some View {
        Section {
            if vm.featureRegistered {
                Label(String(localized: "pet.edit.feature.registered"), systemImage: "checkmark.circle.fill")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensSuccess)
            }

            if vm.isRegisteringFeatures {
                HStack(spacing: Spacing.md) {
                    ProgressView()
                    Text(String(localized: "pet.edit.feature.progress \(vm.featureRegistrationProgress)/\(selectedFeatureItems.count)"))
                        .font(.bodyPrimary)
                }
                Button(String(localized: "common.cancel")) { vm.cancelFeatureRegistration() }
                    .font(.caption)
            } else {
                // PhotosPicker 的 label 闭包是 Sendable：先取出局部值，不在闭包内读 MainActor 隔离属性
                let isRegistered = vm.featureRegistered
                let registerTitle = isRegistered
                    ? String(localized: "pet.edit.feature.reregister")
                    : String(localized: "pet.edit.feature.register")
                PhotosPicker(
                    selection: $selectedFeatureItems,
                    maxSelectionCount: PetFormConstants.maxRegistrationPhotos,
                    matching: .images
                ) {
                    Label(registerTitle, systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!vm.isFeatureRegistrationAvailable)

                if !vm.isFeatureRegistrationAvailable {
                    Text(String(localized: "pet.edit.feature.unavailable"))
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                }

                if !selectedFeatureItems.isEmpty {
                    Text(String(localized: "pet.edit.feature.selected \(selectedFeatureItems.count)"))
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                    Button {
                        loadAndRegister(vm)
                    } label: {
                        Text(String(localized: "pet.edit.feature.start"))
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
            Text(String(localized: "pet.edit.section.feature"))
        } footer: {
            Text(vm.featureRegistered
                 ? String(localized: "pet.edit.feature.footer.update \(PetFormConstants.minRegistrationPhotos) \(PetFormConstants.maxRegistrationPhotos)")
                 : String(localized: "pet.edit.feature.footer.new \(PetFormConstants.minRegistrationPhotos) \(PetFormConstants.maxRegistrationPhotos)"))
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

        return Section(String(localized: "pet.edit.section.dates")) {
            DatePicker(
                String(localized: "pet.edit.birthday"),
                selection: Binding(
                    get: { vm.form.birthday ?? Date() },
                    set: { vm.updateBirthday($0) }
                ),
                in: dateRange,
                displayedComponents: .date
            )

            DatePicker(
                String(localized: "pet.edit.adoptionDay"),
                selection: Binding(
                    get: { vm.form.adoptionDay ?? Date() },
                    set: { vm.updateAdoptionDay($0) }
                ),
                in: dateRange,
                displayedComponents: .date
            )

            // 清除日期
            if vm.form.birthday != nil || vm.form.adoptionDay != nil {
                Button(String(localized: "pet.edit.clearDates"), role: .destructive) {
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
                        .font(.system(size: 5)) // ui-token:ok 列表项目符号圆点
                        .foregroundStyle(Color.milensPrimary)
                    Text(note)
                        .font(.bodyPrimary)
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        vm.removeNoteItem(at: index)
                    } label: {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }
                }
            }

            // 新增备忘输入
            HStack {
                TextField(String(localized: "pet.edit.note.placeholder"), text: $newNoteItem)
                    .font(.bodyPrimary)
                    .onSubmit { addNote(vm) }
                Button {
                    addNote(vm)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .disabled(newNoteItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text(String(localized: "pet.edit.section.notes"))
        } footer: {
            Text(String(localized: "pet.edit.note.footer \(PetFormConstants.maxNoteItemLength)"))
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
                    if let pet = try vm.latestPet() {
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
        do {
            if let pet = try viewModel?.deletePet() {
                // 撤销该宠物的纪念提醒
                if let notifyService {
                    Task { await notifyService.removeReminders(for: pet) }
                }
            }
        } catch {
            logger.error("deletePet: 删除档案失败（\(self.petID)，\(error.localizedDescription)）")
        }
        dismiss()
    }
}
