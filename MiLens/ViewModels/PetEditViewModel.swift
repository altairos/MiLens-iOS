//  PetEditViewModel —— 宠物档案编辑状态机（@Observable）。
//  持有可编辑表单状态 + 原始快照（未保存判定），编排加载/校验/保存。
//  决策通过 PetFormLogic 纯函数完成（DESIGN.md §4）。
//  对应源端 PetEditPage（翻译 PetFormViewModel 编排部分）。
//  特征注册：PhotosPicker 选 8–15 张 → PetMatcher.registerPetFeatures 提取并写入
//  Pet.featureData（对应源端 PetEditPage 注册流程；模型缺失时按钮禁用并提示）。

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

    // MARK: - 特征注册状态（对应源端 PetEditPage 注册区块）

    /// 该宠物已注册视觉特征（loadPet 时读取 featureData）
    var featureRegistered = false
    /// 正在提取特征（PhotosPicker 选图后置灰按钮）
    var isRegisteringFeatures = false
    /// 特征提取进度（已处理张数）
    var featureRegistrationProgress = 0
    /// 注册结果消息（成功/失败原因，展示在区块 footer）
    var featureRegistrationMessage = ""

    // MARK: - 内部

    private var petID: UUID?
    private var originalSnapshot: PetFormLogic.PetComparisonSnapshot = .init(
        name: "", species: .unknown, gender: .unknown,
        birthday: nil, adoptionDay: nil, notes: "", avatarPath: ""
    )
    private(set) var avatarPath = ""
    private var featureTask: Task<Void, Never>?

    private let petRepo: any PetRepositoryProtocol
    private let clipService: (any ClipInference)?

    init(petRepo: any PetRepositoryProtocol, clipService: (any ClipInference)? = nil) {
        self.petRepo = petRepo
        self.clipService = clipService
    }

    // MARK: - 加载

    func loadPet(id: UUID) {
        isLoading = true
        petID = id
        let pet: Pet
        do {
            guard let found = try petRepo.getPet(id: id) else {
                isLoading = false
                errorMessage = String(localized: "pet.profile.loadFailed")
                return
            }
            pet = found
        } catch {
            isLoading = false
            errorMessage = String(localized: "pet.profile.loadFailed")
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
        featureRegistered = pet.featureData != nil
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
                errorMessage = String(localized: "pet.profile.loadFailed")
                return false
            }
            pet = found
        } catch {
            errorMessage = String(localized: "pet.profile.loadFailed")
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
            // 编辑宠物后刷新 Widget 快照（§6.1）
            WidgetReload.notifyDataChanged()
        } catch {
            errorMessage = "保存失败，请重试"
            isSaving = false
            return false
        }
        isSaving = false
        return true
    }

    // MARK: - 视觉特征注册（对应源端 PetEditPage 注册流程）

    /// 用选中的照片注册/更新宠物视觉特征（8–15 张，经 PetMatcher 提取聚合后写入 DB）。
    /// 异步执行：进度与结果分别写入 featureRegistrationProgress / featureRegistrationMessage。
    func registerFeature(imageDatas: [Data]) {
        guard let petID, !isRegisteringFeatures else { return }
        // 数量校验（对应源端 resolveRegistrationValidation）
        if imageDatas.count < PetFormConstants.minRegistrationPhotos {
            featureRegistrationMessage = "请至少选择 \(PetFormConstants.minRegistrationPhotos) 张照片"
            return
        }
        if imageDatas.count > PetFormConstants.maxRegistrationPhotos {
            featureRegistrationMessage = "最多选择 \(PetFormConstants.maxRegistrationPhotos) 张照片"
            return
        }
        isRegisteringFeatures = true
        featureRegistrationProgress = 0
        featureRegistrationMessage = ""
        featureTask = Task { [weak self] in
            guard let self else { return }
            let matcher = PetMatcher(petRepo: self.petRepo, clipService: self.clipService)
            let ok = await matcher.registerPetFeatures(
                petID: petID, imageDatas: imageDatas
            ) { [weak self] progress in
                self?.featureRegistrationProgress = progress
            }
            self.isRegisteringFeatures = false
            if ok {
                self.featureRegistered = true
                self.featureRegistrationMessage = "已注册 \(imageDatas.count) 张照片的视觉特征"
            } else {
                self.featureRegistrationMessage = "注册失败：\(matcher.lastRegisterDiagnostics)"
            }
            self.featureTask = nil
        }
    }

    /// 取消进行中的特征注册（任务取消；已在提取中的单张完成后停止）。
    func cancelFeatureRegistration() {
        featureTask?.cancel()
        featureTask = nil
        isRegisteringFeatures = false
    }

    // MARK: - 页面数据操作（分层收敛：View 不再直连 Repository）

    /// AI 特征注册是否可用（CLIP 模型就绪判定；替代 View 直接读 clipService）。
    var isFeatureRegistrationAvailable: Bool {
        clipService != nil
    }

    /// 读取当前档案的最新记录（保存后提醒重调度 / 删除前快照）。
    func latestPet() throws -> Pet? {
        guard let petID else { return nil }
        return try petRepo.getPet(id: petID)
    }

    /// 删除当前档案。返回被删除的记录（调用方用于撤销纪念提醒）；档案不存在返回 nil。
    func deletePet() throws -> Pet? {
        guard let petID else { return nil }
        guard let pet = try petRepo.getPet(id: petID) else { return nil }
        try petRepo.deletePet(pet)
        // 删除宠物后刷新 Widget 快照（§6.1）
        WidgetReload.notifyDataChanged()
        return pet
    }
}
