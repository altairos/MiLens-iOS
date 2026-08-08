//  PetEditView —— 宠物档案编辑（route .petEdit，对应源端 pages/PetEditPage.ets）。
//  PetEditViewModel（@Observable）驱动表单状态，校验/保存/未保存判定通过 PetFormLogic 纯函数。
//  P3 实现：名称/物种/性别/生日/领养日/备忘条目编辑 + 保存 + 删除 + 未保存确认。
//  头像裁切/视觉特征注册后置 V1.x（依赖图片编辑器 + CLIP 模型）。

import SwiftUI

struct PetEditView: View {
    let petID: UUID

    @Environment(\.petRepository) private var petRepo
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PetEditViewModel?
    @State private var newNoteItem = ""
    @State private var showDeleteConfirm = false
    @State private var showBackConfirm = false

    private let dateRange: ClosedRange<Date> = {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: 2000, month: 1, day: 1))!
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let vm = viewModel, !vm.isLoading {
                    Button("保存") { save(vm) }
                        .font(.buttonLabel)
                        .disabled(vm.isSaving)
                }
            }
        }
        .task {
            if viewModel == nil {
                let vm = PetEditViewModel(petRepo: petRepo)
                vm.loadPet(id: petID)
                viewModel = vm
            }
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
            dismiss()
        }
    }

    private func deletePet() {
        if let pet = try? petRepo.getPet(id: petID) {
            try? petRepo.deletePet(pet)
        }
        dismiss()
    }
}
