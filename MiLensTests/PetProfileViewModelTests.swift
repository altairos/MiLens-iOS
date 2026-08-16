//  PetProfileViewModelTests —— 宠物档案 ViewModel 状态机测试。
//  覆盖：列表加载（成功/失败清空）、建档校验（空白名、free=1 / pro=20 数量上限）、
//  插入失败文案、成功后清错 + 名称去空格持久化、同日生日彩蛋（07-03）、
//  表单复位、删除（成功移除 / 失败静默保持列表）。

import XCTest
@testable import MiLens

/// 仓储注入错误。
struct RepositoryFailure: Error {}

/// 可注入失败的宠物仓储：转发内存实现，按需在指定方法抛错。
/// internal——供 PetProfile / Timeline 等 ViewModel 测试复用。
@MainActor
final class FlakyPetRepository: PetRepositoryProtocol {
    private let base = InMemoryPetRepository()
    var failGetAll = false
    var failGetPet = false
    var failInsert = false
    var failUpdatePet = false
    var failDelete = false
    var failAddEvent = false

    func getAllPets() throws -> [Pet] {
        guard !failGetAll else { throw RepositoryFailure() }
        return try base.getAllPets()
    }
    func getPet(id: UUID) throws -> Pet? {
        guard !failGetPet else { throw RepositoryFailure() }
        return try base.getPet(id: id)
    }
    func insertPet(_ pet: Pet) throws {
        guard !failInsert else { throw RepositoryFailure() }
        try base.insertPet(pet)
    }
    func updatePet(_ pet: Pet) throws {
        guard !failUpdatePet else { throw RepositoryFailure() }
        try base.updatePet(pet)
    }
    func deletePet(_ pet: Pet) throws {
        guard !failDelete else { throw RepositoryFailure() }
        try base.deletePet(pet)
    }
    func refreshPhotoCount(for pet: Pet) throws { try base.refreshPhotoCount(for: pet) }
    func updateFeatureData(_ pet: Pet, data: Data?) throws { try base.updateFeatureData(pet, data: data) }
    func addEvent(_ event: PetEvent, to pet: Pet) throws {
        guard !failAddEvent else { throw RepositoryFailure() }
        try base.addEvent(event, to: pet)
    }
}

@MainActor
final class PetProfileViewModelTests: XCTestCase {

    private func makeVM(pets: [Pet] = [], isPro: Bool = false) -> PetProfileViewModel {
        PetProfileViewModel(petRepo: InMemoryPetRepository(pets: pets), isPro: isPro)
    }

    /// UTC 2024-07-03 12:00:00Z（彩蛋生日 MM-DD = 07-03）。
    private let easterEggBirthday = Date(timeIntervalSince1970: 1_719_968_400)
    /// UTC 2024-12-25 12:00:00Z（非彩蛋日期）。
    private let ordinaryBirthday = Date(timeIntervalSince1970: 1_735_128_000)

    // MARK: - 列表加载

    func testLoadPetsPopulatesList() {
        let vm = makeVM(pets: [Pet(name: "小橘"), Pet(name: "小白")])

        vm.loadPets()

        XCTAssertEqual(vm.pets.map(\.name), ["小橘", "小白"])
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadPetsClearsListOnFailure() throws {
        let repo = FlakyPetRepository()
        try repo.insertPet(Pet(name: "小橘"))
        let vm = PetProfileViewModel(petRepo: repo)

        vm.loadPets()
        XCTAssertEqual(vm.pets.count, 1)

        repo.failGetAll = true
        vm.loadPets()
        XCTAssertTrue(vm.pets.isEmpty, "加载失败应清空列表（对应源端失败兜底）")
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - 建档校验

    func testAddPetRejectsBlankName() {
        let vm = makeVM()

        let ok = vm.addPet(name: "   ")

        XCTAssertFalse(ok)
        XCTAssertEqual(vm.addError, PetProfileLogic.validateNewPetName("   "))
        XCTAssertEqual(vm.pets.count, 0)
    }

    func testAddPetEnforcesFreeLimitOfOneThenAllowsPro() {
        // free 用户上限 1 只：已有 1 只时新增被拒（addPet 校验用 VM 内存列表，须先 load）
        let vm = makeVM(pets: [Pet(name: "小橘")], isPro: false)
        vm.loadPets()

        XCTAssertFalse(vm.addPet(name: "小白"))
        XCTAssertEqual(
            vm.addError,
            PetProfileLogic.checkPetCountLimit(
                currentCount: 1, maxPets: CommercialRules.petLimit(isPro: false)))

        // 升级 Pro 后同一操作放行（上限 20）
        vm.updateEntitlement(isPro: true)
        XCTAssertTrue(vm.addPet(name: "小白"))
        XCTAssertEqual(vm.pets.count, 2)
    }

    func testAddPetPersistsTrimmedNameAndClearsError() {
        let vm = makeVM()
        // 先制造一次校验失败，验证成功后被清空
        _ = vm.addPet(name: "")
        XCTAssertFalse(vm.addError.isEmpty)

        let ok = vm.addPet(name: "  小白  ")

        XCTAssertTrue(ok)
        XCTAssertEqual(vm.addError, "")
        XCTAssertEqual(vm.pets.map(\.name), ["小白"], "名称应去除首尾空格后持久化")
    }

    func testAddPetReportsInsertFailure() {
        let repo = FlakyPetRepository()
        repo.failInsert = true
        let vm = PetProfileViewModel(petRepo: repo)

        XCTAssertFalse(vm.addPet(name: "小橘"))
        XCTAssertEqual(vm.addError, "保存失败，请重试")
    }

    // MARK: - 彩蛋（同日生日 07-03）

    func testAddPetTriggersEasterEggOnlyOnJulyThird() {
        // 命中：生日 07-03
        let hit = makeVM()
        XCTAssertTrue(hit.addPet(name: "小橘", birthday: easterEggBirthday))
        XCTAssertTrue(hit.showEasterEgg)

        // 未命中：其他日期 / 未填生日
        let miss = makeVM()
        XCTAssertTrue(miss.addPet(name: "小白", birthday: ordinaryBirthday))
        XCTAssertFalse(miss.showEasterEgg)

        let noBirthday = makeVM()
        XCTAssertTrue(noBirthday.addPet(name: "小黑"))
        XCTAssertFalse(noBirthday.showEasterEgg)
    }

    // MARK: - 表单复位

    func testResetFormClearsErrorAndEasterEgg() {
        let vm = makeVM()
        _ = vm.addPet(name: "小橘", birthday: easterEggBirthday)
        XCTAssertTrue(vm.addError.isEmpty, "建档成功后 addError 应为空")
        XCTAssertTrue(vm.showEasterEgg)

        vm.resetForm()

        XCTAssertEqual(vm.addError, "")
        XCTAssertFalse(vm.showEasterEgg)
    }

    // MARK: - 删除

    func testDeletePetRemovesFromList() {
        let petA = Pet(name: "小橘")
        let petB = Pet(name: "小白")
        let vm = makeVM(pets: [petA, petB])

        vm.deletePet(petA)

        XCTAssertEqual(vm.pets.map(\.name), ["小白"])
    }

    func testDeletePetKeepsListOnFailure() {
        let repo = FlakyPetRepository()
        let pet = Pet(name: "小橘")
        try? repo.insertPet(pet)
        repo.failDelete = true
        let vm = PetProfileViewModel(petRepo: repo)
        vm.loadPets()

        vm.deletePet(pet)

        XCTAssertEqual(vm.pets.count, 1, "删除失败应静默保持列表不变")
    }
}
