//  PetEditViewModel —— 宠物档案编辑状态机（@Observable）。
//  持有可编辑表单状态 + 原始快照（未保存判定），编排加载/校验/保存。
//  决策通过 PetFormLogic 纯函数完成（DESIGN.md §4）。
//  对应源端 PetEditPage（翻译 PetFormViewModel 编排部分）。

import Foundation
import os

@MainActor
@Observable
final class PetEditViewModel {

    private let logger = Logger(subsystem: "com.milens.app", category: "PetEdit")

    // MARK: - 显示层状态

    var form = PetFormState.empty
    var isSaving = false
    var errorMessage = ""
    /// 加载完成标志（对应源端 isLoading）
    var isLoading = false
    /// 保存成功后通知视图 dismiss（对应源端 pop 页面）
    var didSaveSuccessfully = false

    // MARK: - 内部

    private var petID: UUID?
    private var originalSnapshot: PetFormLogic.PetComparisonSnapshot = .init(
        name: "", species: .unknown, gender: .unknown,
        birthday: nil, adoptionDay: nil, notes: "", avatarPath: ""
    )
    private var avatarPath = ""

    private let petRepo: any PetRepositoryProtocol

    init(petRepo: any PetRepositoryProtocol) {
        self.petRepo = petRepo
    }

    // MARK: - 加载

    func loadPet(id: UUID) {
        isLoading = true
        petID = id
        let pet: Pet
        do {
            guard let found = try petRepo.getPet(id: id) else {
                isLoading = false
                errorMessage = "档案加载失败"
                return
            }
            pet = found
        } catch {
            isLoading = false
            errorMessage = "档案加载失败"
            logger.error("loadPet: 读取档案失败（\(id)，\(error.localizedDescription)）")
            return
        }
        form.name = pet.name
        form.species = pet.species
        form.gender = pet.gender
        form.birthday = pet.birthday
        form.adoptionDay = pet.adoptionDay
        form.noteItems = PetFormLogic.parseNoteItems(pet.notes)
        avatarPath = pet.avatarPath
        originalSnapshot = makeSnapshot()
        errorMessage = ""
        isLoading = false
    }

    // MARK: - 表单更新便捷方法

    func updateName(_ value: String) { form.name = value }
    func updateSpecies(_ value: Species) { form.species = value }
    func updateGender(_ value: Gender) { form.gender = value }
    func updateBirthday(_ value: Date?) { form.birthday = value }
    func updateAdoptionDay(_ value: Date?) { form.adoptionDay = value }
    func updateAvatarPath(_ value: String) { avatarPath = value }

    // MARK: - 备注条目

    /// 尝试新增备忘条目。返回 true 表示成功，false 表示校验拒绝（errorMessage 已填充）。
    @discardableResult
    func addNoteItem(_ input: String) -> Bool {
        let result = PetFormLogic.validateAndBuildNoteItem(input)
        if !result.ok {
            if !result.error.isEmpty { errorMessage = result.error }
            return false
        }
        form.noteItems.append(result.item)
        errorMessage = ""
        return true
    }

    func removeNoteItem(at index: Int) {
        guard form.noteItems.indices.contains(index) else { return }
        form.noteItems.remove(at: index)
    }

    // MARK: - 未保存判定

    var hasUnsavedChanges: Bool {
        PetFormLogic.hasUnsavedChanges(current: makeSnapshot(), original: originalSnapshot)
    }

    private func makeSnapshot() -> PetFormLogic.PetComparisonSnapshot {
        PetFormLogic.PetComparisonSnapshot(
            name: form.name, species: form.species, gender: form.gender,
            birthday: form.birthday, adoptionDay: form.adoptionDay,
            notes: PetFormLogic.formatNoteItems(form.noteItems),
            avatarPath: avatarPath
        )
    }

    // MARK: - 保存

    /// 保存档案。返回 true 表示成功，false 表示校验失败或写入失败（errorMessage 已填充）。
    @discardableResult
    func save() -> Bool {
        guard let petID else {
            errorMessage = "档案未加载"
            return false
        }
        // 名称校验
        if let nameError = PetProfileLogic.validateNewPetName(form.name) {
            errorMessage = nameError
            return false
        }
        // 备注长度校验
        if let noteError = PetFormLogic.validateNoteItemLength(form.noteItems) {
            errorMessage = noteError
            return false
        }
        let pet: Pet
        do {
            guard let found = try petRepo.getPet(id: petID) else {
                errorMessage = "档案加载失败"
                return false
            }
            pet = found
        } catch {
            errorMessage = "档案加载失败"
            logger.error("save: 读取档案失败（\(self.petID?.uuidString ?? "nil")，\(error.localizedDescription)）")
            return false
        }
        pet.name = form.name.trimmingCharacters(in: .whitespaces)
        pet.species = form.species
        pet.gender = form.gender
        pet.birthday = form.birthday
        pet.adoptionDay = form.adoptionDay
        pet.notes = PetFormLogic.formatNoteItems(form.noteItems)
        pet.avatarPath = avatarPath
        pet.updatedAt = Date()

        isSaving = true
        do {
            try petRepo.updatePet(pet)
            originalSnapshot = makeSnapshot()
            errorMessage = ""
            didSaveSuccessfully = true
        } catch {
            errorMessage = "保存失败，请重试"
            isSaving = false
            return false
        }
        isSaving = false
        return true
    }
}
