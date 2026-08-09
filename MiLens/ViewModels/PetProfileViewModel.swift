//  PetProfileViewModel —— 宠物档案列表/建档状态机（@Observable）。
//  持有宠物列表、建档表单状态、错误文案、彩蛋提示。
//  决策通过 PetProfileLogic 纯函数完成（DESIGN.md §4）。
//  对应源端 PetProfilePage（列表 + 新增宠物表单部分）。

import Foundation

@MainActor
@Observable
final class PetProfileViewModel {

    // MARK: - 显示层状态

    var pets: [Pet] = []
    var isLoading = false
    /// 建档表单错误文案（对应源端 addError）
    var addError = ""
    /// 彩蛋提示（同日生日）
    var showEasterEgg = false

    // MARK: - 依赖

    private let petRepo: any PetRepositoryProtocol
    private var isPro: Bool

    init(petRepo: any PetRepositoryProtocol, isPro: Bool = false) {
        self.petRepo = petRepo
        self.isPro = isPro
    }

    func updateEntitlement(isPro: Bool) {
        self.isPro = isPro
    }

    // MARK: - 列表加载

    func loadPets() {
        isLoading = true
        do {
            pets = try petRepo.getAllPets()
        } catch {
            pets = []
        }
        isLoading = false
    }

    // MARK: - 新增宠物

    /// 新增宠物。返回 true 表示成功（并可能触发彩蛋），false 表示校验失败（addError 已填充）。
    @discardableResult
    func addPet(
        name: String, species: Species = .unknown, gender: Gender = .unknown,
        birthday: Date? = nil, adoptionDay: Date? = nil
    ) -> Bool {
        // 名称校验
        if let nameError = PetProfileLogic.validateNewPetName(name) {
            addError = nameError
            return false
        }
        // 数量上限校验
        if let countError = PetProfileLogic.checkPetCountLimit(
            currentCount: pets.count,
            maxPets: CommercialRules.petLimit(isPro: isPro)
        ) {
            addError = countError
            return false
        }
        let pet = Pet(
            name: name.trimmingCharacters(in: .whitespaces),
            species: species, gender: gender,
            birthday: birthday, adoptionDay: adoptionDay
        )
        do {
            try petRepo.insertPet(pet)
        } catch {
            addError = "保存失败，请重试"
            return false
        }
        addError = ""
        loadPets()

        // 彩蛋：同日生日
        let monthDay = PetProfileLogic.monthDayString(from: birthday)
        showEasterEgg = PetProfileLogic.shouldShowEasterEgg(monthDay: monthDay)
        return true
    }

    /// 重置建档表单状态（关闭弹窗/Sheet 时调用）。
    func resetForm() {
        addError = ""
        showEasterEgg = false
    }

    // MARK: - 删除宠物

    func deletePet(_ pet: Pet) {
        do {
            try petRepo.deletePet(pet)
            loadPets()
        } catch {
            // 静默失败，列表保持不变
        }
    }
}
