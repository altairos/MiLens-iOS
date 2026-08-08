//  AddPetSheet —— 新增宠物建档表单（对应源端 components/pet/AddPetSheet.ets）。
//  作为 .sheet 弹出，收集名称/物种/性别/生日/领养日，提交时调用 ViewModel.addPet。
//  错误文案与彩蛋由父视图的 PetProfileViewModel 管理。

import SwiftUI

struct AddPetSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 父视图传入的 ViewModel（持有校验/入库/彩蛋逻辑）。
    var viewModel: PetProfileViewModel

    // 表单本地状态
    @State private var name = ""
    @State private var species: Species = .unknown
    @State private var gender: Gender = .unknown
    @State private var birthday: Date = Date()
    @State private var hasBirthday = false
    @State private var adoptionDay: Date = Date()
    @State private var hasAdoptionDay = false

    private let dateRange: ClosedRange<Date> = {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        return start...Date()
    }()

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                datesSection
                speciesGenderSection
                if !viewModel.addError.isEmpty {
                    errorSection
                }
            }
            .navigationTitle("添加伙伴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { viewModel.resetForm(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") { submit() }
                        .font(.buttonLabel)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - 表单分区

    private var nameSection: some View {
        Section("基本信息") {
            HStack {
                Text(PetProfileLogic.speciesEmoji(species))
                    .font(.title2)
                TextField("给它起个名字", text: $name)
                    .font(.bodyPrimary)
                    .submitLabel(.done)
            }
        }
    }

    private var datesSection: some View {
        Section("重要日期") {
            Toggle("记录生日", isOn: $hasBirthday)
            if hasBirthday {
                DatePicker("生日", selection: $birthday, in: dateRange,
                           displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
            Toggle("记录领养日", isOn: $hasAdoptionDay)
            if hasAdoptionDay {
                DatePicker("领养日", selection: $adoptionDay, in: dateRange,
                           displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
        }
    }

    private var speciesGenderSection: some View {
        Section("物种与性别") {
            Picker("物种", selection: $species) {
                ForEach(Species.allCases, id: \.self) { s in
                    Text(PetDisplayLogic.speciesDisplayName(s)).tag(s)
                }
            }
            Picker("性别", selection: $gender) {
                ForEach(Gender.allCases, id: \.self) { g in
                    Text(PetDisplayLogic.genderDisplayName(g)).tag(g)
                }
            }
        }
    }

    private var errorSection: some View {
        Section {
            Label(viewModel.addError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.milensDanger)
                .font(.caption)
        }
    }

    // MARK: - 提交

    private func submit() {
        let ok = viewModel.addPet(
            name: name,
            species: species,
            gender: gender,
            birthday: hasBirthday ? birthday : nil,
            adoptionDay: hasAdoptionDay ? adoptionDay : nil
        )
        if ok {
            resetLocalForm()
            dismiss()
        }
    }

    private func resetLocalForm() {
        name = ""
        species = .unknown
        gender = .unknown
        hasBirthday = false
        hasAdoptionDay = false
    }
}
