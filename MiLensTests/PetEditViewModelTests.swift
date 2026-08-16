//  PetEditViewModelTests —— 宠物档案编辑 ViewModel 状态机测试。
//  覆盖：加载（填充/不存在/读取失败）、备注条目（trim 新增/空输入静默/超长、越界删除）、
//  未保存判定、保存（未加载/空名/备注超长/档案已删/写入失败/成功回写与快照重置）、
//  特征注册（数量校验/成功进度与持久化/CLIP 缺失失败/进行中取消复位/可用性透传）、
//  latestPet / deletePet。

import XCTest
@testable import MiLens

/// 挂起式 CLIP mock：detect 停在 gate 处直至放行，用于构造「注册进行中」窗口
/// （验证取消语义；MockClipInference 无法挂起）。
@MainActor
private final class GatedClipInference: ClipInference {
    private let embedding: [Float]
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var detectCallCount = 0

    init(embedding: [Float]? = nil) {
        self.embedding = embedding ?? MockClipInference.randomEmbedding()
    }

    func detect(imageData: Data) async throws -> ClipDetectionResult {
        detectCallCount += 1
        await withCheckedContinuation { waiters.append($0) }
        return ClipDetectionResult(
            isPet: true, labels: [], species: "cat", embedding: embedding,
            topLabel: "cat", topConfidence: 0.9, usedClipModel: true, diagnostics: "")
    }

    func extractFallbackEmbedding(imageData: Data) async throws -> [Float] { embedding }

    func openGate() {
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
final class PetEditViewModelTests: XCTestCase {

    /// 轮询等待条件成立（主线程让出，最多 ~2.5s；与 BackupViewModelTests 一致）。
    private func waitUntil(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - 夹具

    /// UTC 2023-11-14 22:13:20Z（生日）。
    private let birthday = Date(timeIntervalSince1970: 1_700_000_000)
    /// UTC 2024-01-10 10:00:00Z（领养日）。
    private let adoptionDay = Date(timeIntervalSince1970: 1_704_876_000)

    /// 已建档宠物（notes 含两条标准前缀格式；updatedAt 起点 epoch 0 便于断言刷新）。
    private func makeSeededPet(featureData: Data? = nil) -> Pet {
        Pet(name: "小橘", species: .cat, gender: .male,
            birthday: birthday, adoptionDay: adoptionDay,
            avatarPath: "avatar://x", notes: "· 怕生\n· 爱吃冻干",
            featureData: featureData,
            updatedAt: Date(timeIntervalSince1970: 0))
    }

    /// pet 插入 repo 后 loadPet 完成的 VM。
    private func makeLoadedVM(
        repo: FlakyPetRepository, pet: Pet,
        clipService: (any ClipInference)? = nil
    ) -> PetEditViewModel {
        let vm = PetEditViewModel(petRepo: repo, clipService: clipService)
        vm.loadPet(id: pet.id)
        return vm
    }

    private func seed(_ pet: Pet, into repo: FlakyPetRepository) -> Pet {
        try? repo.insertPet(pet)
        return pet
    }

    // MARK: - 加载

    func testLoadPetFillsFormFromRecord() {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(featureData: Data([1, 2, 3])), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)

        XCTAssertEqual(vm.form.name, "小橘")
        XCTAssertEqual(vm.form.species, .cat)
        XCTAssertEqual(vm.form.gender, .male)
        XCTAssertEqual(vm.form.birthday, birthday)
        XCTAssertEqual(vm.form.adoptionDay, adoptionDay)
        XCTAssertEqual(vm.form.noteItems, ["怕生", "爱吃冻干"], "notes 应剥前缀解析为条目")
        XCTAssertEqual(vm.avatarPath, "avatar://x")
        XCTAssertTrue(vm.featureRegistered, "featureData 非空应点亮已注册标志")
        XCTAssertEqual(vm.errorMessage, "")
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.hasUnsavedChanges)
    }

    func testLoadPetMissingRecordReportsError() {
        let vm = PetEditViewModel(petRepo: FlakyPetRepository())

        vm.loadPet(id: UUID())

        XCTAssertEqual(vm.errorMessage, String(localized: "pet.profile.loadFailed"))
        XCTAssertEqual(vm.form, PetFormState.empty, "表单应保持初始空状态")
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadPetRepositoryFailureReportsError() {
        let repo = FlakyPetRepository()
        repo.failGetPet = true
        let vm = PetEditViewModel(petRepo: repo)

        vm.loadPet(id: UUID())

        XCTAssertEqual(vm.errorMessage, String(localized: "pet.profile.loadFailed"))
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - 备注条目

    func testAddNoteItemTrimsInputAndClearsError() {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)
        vm.errorMessage = "残留错误"

        XCTAssertTrue(vm.addNoteItem("  爱睡觉  "))

        XCTAssertEqual(vm.form.noteItems, ["怕生", "爱吃冻干", "爱睡觉"])
        XCTAssertEqual(vm.errorMessage, "", "成功新增应清空错误")
    }

    func testAddNoteItemSilentlyRejectsBlankInput() {
        let vm = PetEditViewModel(petRepo: FlakyPetRepository())
        vm.errorMessage = "保留原错误"

        XCTAssertFalse(vm.addNoteItem("   "))

        XCTAssertTrue(vm.form.noteItems.isEmpty)
        XCTAssertEqual(vm.errorMessage, "保留原错误", "空输入静默拒绝，不应覆盖错误")
    }

    func testAddNoteItemRejectsOverlongInput() {
        let vm = PetEditViewModel(petRepo: FlakyPetRepository())
        let overlong = String(repeating: "长", count: PetFormConstants.maxNoteItemLength + 1)

        XCTAssertFalse(vm.addNoteItem(overlong))

        XCTAssertEqual(
            vm.errorMessage, PetFormLogic.validateAndBuildNoteItem(overlong).error,
            "超长拒绝文案应与纯函数一致")
        XCTAssertTrue(vm.form.noteItems.isEmpty)
    }

    func testRemoveNoteItemIgnoresOutOfBoundsIndex() {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)

        vm.removeNoteItem(at: 9)
        XCTAssertEqual(vm.form.noteItems, ["怕生", "爱吃冻干"])

        vm.removeNoteItem(at: 0)
        XCTAssertEqual(vm.form.noteItems, ["爱吃冻干"])
    }

    // MARK: - 未保存判定

    func testHasUnsavedChangesTracksEditsAndReverts() {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)
        XCTAssertFalse(vm.hasUnsavedChanges)

        vm.updateName("小白")
        XCTAssertTrue(vm.hasUnsavedChanges)

        vm.updateName("小橘")
        XCTAssertFalse(vm.hasUnsavedChanges, "改回原值应视为无变化")

        vm.updateAvatarPath("avatar://y")
        XCTAssertTrue(vm.hasUnsavedChanges, "头像变更也应计入未保存")
    }

    // MARK: - 保存

    func testSaveWithoutLoadedPetFails() {
        let vm = PetEditViewModel(petRepo: FlakyPetRepository())

        XCTAssertFalse(vm.save())

        XCTAssertEqual(vm.errorMessage, String(localized: "pet.edit.notLoaded"))
    }

    func testSaveRejectsBlankName() {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)
        vm.updateName("   ")

        XCTAssertFalse(vm.save())

        XCTAssertEqual(vm.errorMessage, PetProfileLogic.validateNewPetName("   "))
        XCTAssertFalse(vm.didSaveSuccessfully)
    }

    func testSaveRejectsOverlongNoteItem() {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)
        // 直接注入超长条目（addNoteItem 无法产生，模拟历史脏数据路径）
        vm.form.noteItems.append(
            String(repeating: "长", count: PetFormConstants.maxNoteItemLength + 1))

        XCTAssertFalse(vm.save())

        XCTAssertEqual(
            vm.errorMessage, PetFormLogic.validateNoteItemLength(vm.form.noteItems),
            "保存前的备注长度校验应拦截超长条目")
    }

    func testSaveFailsWhenPetDeletedAfterLoad() {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)
        try? repo.deletePet(pet)

        XCTAssertFalse(vm.save())

        XCTAssertEqual(vm.errorMessage, String(localized: "pet.profile.loadFailed"))
        XCTAssertFalse(vm.didSaveSuccessfully)
    }

    func testSaveReportsWriteFailure() {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)
        vm.updateName("小白")
        repo.failUpdatePet = true

        XCTAssertFalse(vm.save())

        XCTAssertEqual(vm.errorMessage, String(localized: "pet.edit.saveFailed"))
        XCTAssertFalse(vm.isSaving)
        XCTAssertFalse(vm.didSaveSuccessfully)
        XCTAssertTrue(vm.hasUnsavedChanges, "写入失败后修改应仍视为未保存")
    }

    func testSavePersistsTrimmedFieldsAndResetsSnapshot() throws {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)
        vm.updateName("  小白  ")
        vm.updateSpecies(.dog)
        vm.updateGender(.female)
        vm.addNoteItem("爱睡觉")
        vm.updateAvatarPath("avatar://y")

        XCTAssertTrue(vm.save())

        XCTAssertTrue(vm.didSaveSuccessfully)
        XCTAssertFalse(vm.isSaving)
        XCTAssertEqual(vm.errorMessage, "")
        XCTAssertFalse(vm.hasUnsavedChanges, "保存成功应重置未保存判定")

        let saved = try XCTUnwrap(repo.getPet(id: pet.id))
        XCTAssertEqual(saved.name, "小白", "名称应 trim 后持久化")
        XCTAssertEqual(saved.species, .dog)
        XCTAssertEqual(saved.gender, .female)
        XCTAssertEqual(saved.notes, "· 怕生\n· 爱吃冻干\n· 爱睡觉", "备注应按存储格式回写")
        XCTAssertEqual(saved.avatarPath, "avatar://y")
        XCTAssertGreaterThan(
            saved.updatedAt.timeIntervalSince1970, 1,
            "保存应刷新 updatedAt（夹具起点为 epoch 0）")
    }

    // MARK: - 特征注册

    func testRegisterFeatureValidatesPhotoCount() {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet, clipService: MockClipInference())

        vm.registerFeature(imageDatas: Array(repeating: Data([1]), count: 7))
        XCTAssertEqual(
            vm.featureRegistrationMessage,
            String(localized: "pet.edit.feature.minPhotos \(PetFormConstants.minRegistrationPhotos)"))
        XCTAssertFalse(vm.isRegisteringFeatures)
        XCTAssertEqual(vm.featureRegistrationProgress, 0)

        vm.registerFeature(imageDatas: Array(repeating: Data([1]), count: 16))
        XCTAssertEqual(
            vm.featureRegistrationMessage,
            String(localized: "pet.edit.feature.maxPhotos \(PetFormConstants.maxRegistrationPhotos)"))
        XCTAssertFalse(vm.isRegisteringFeatures)
    }

    func testRegisterFeatureIgnoredWhenPetNotLoaded() {
        let vm = PetEditViewModel(petRepo: FlakyPetRepository(), clipService: MockClipInference())

        vm.registerFeature(imageDatas: Array(repeating: Data([1]), count: 8))

        XCTAssertFalse(vm.isRegisteringFeatures)
        XCTAssertEqual(vm.featureRegistrationMessage, "")
        XCTAssertEqual(vm.featureRegistrationProgress, 0)
    }

    func testRegisterFeatureSucceedsWithProgressAndPersistsFeatures() async throws {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let clip = MockClipInference()
        let vm = makeLoadedVM(repo: repo, pet: pet, clipService: clip)
        XCTAssertFalse(vm.featureRegistered)

        vm.registerFeature(imageDatas: Array(repeating: Data([1]), count: 8))
        await waitUntil(!vm.isRegisteringFeatures && !vm.featureRegistrationMessage.isEmpty)

        XCTAssertTrue(vm.featureRegistered)
        XCTAssertEqual(vm.featureRegistrationProgress, 8, "每张照片处理完成应推进进度")
        XCTAssertEqual(
            vm.featureRegistrationMessage,
            String(localized: "pet.edit.feature.success \(8)"))
        XCTAssertEqual(clip.detectCallCount, 8)
        let updated = try XCTUnwrap(repo.getPet(id: pet.id))
        XCTAssertNotNil(updated.featureData, "注册成功应写入特征数据")
    }

    func testRegisterFeatureFailsWhenClipUnavailable() async {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet, clipService: nil)

        vm.registerFeature(imageDatas: Array(repeating: Data([1]), count: 8))
        await waitUntil(!vm.isRegisteringFeatures && !vm.featureRegistrationMessage.isEmpty)

        XCTAssertFalse(vm.featureRegistered, "CLIP 缺失时注册不应成功")
        XCTAssertTrue(
            vm.featureRegistrationMessage.contains("0 valid embeddings out of 8"),
            "失败消息应携带 PetMatcher 诊断，实际：\(vm.featureRegistrationMessage)")
    }

    func testCancelFeatureRegistrationResetsInFlightState() async {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let clip = GatedClipInference()
        let vm = makeLoadedVM(repo: repo, pet: pet, clipService: clip)

        vm.registerFeature(imageDatas: Array(repeating: Data([1]), count: 8))
        await waitUntil(vm.isRegisteringFeatures && clip.detectCallCount == 1)

        vm.cancelFeatureRegistration()
        XCTAssertFalse(vm.isRegisteringFeatures, "取消应立即复位进行中标志")

        clip.openGate()
        await waitUntil(!vm.featureRegistrationMessage.isEmpty)
        XCTAssertFalse(vm.isRegisteringFeatures)
    }

    func testIsFeatureRegistrationAvailableMirrorsClipService() {
        XCTAssertFalse(
            PetEditViewModel(petRepo: FlakyPetRepository()).isFeatureRegistrationAvailable)
        XCTAssertTrue(
            PetEditViewModel(petRepo: FlakyPetRepository(), clipService: MockClipInference())
                .isFeatureRegistrationAvailable)
    }

    // MARK: - 页面数据操作

    func testLatestPetReturnsNilBeforeLoadAndPetAfterLoad() throws {
        let repo = FlakyPetRepository()
        XCTAssertNil(try PetEditViewModel(petRepo: repo).latestPet())

        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)

        XCTAssertEqual(try vm.latestPet()?.id, pet.id)
    }

    func testDeletePetReturnsRecordThenNil() throws {
        let repo = FlakyPetRepository()
        let pet = seed(makeSeededPet(), into: repo)
        let vm = makeLoadedVM(repo: repo, pet: pet)

        let deleted = try XCTUnwrap(vm.deletePet())

        XCTAssertEqual(deleted.id, pet.id, "删除应返回被删记录供撤销纪念提醒")
        XCTAssertNil(try repo.getPet(id: pet.id))
        XCTAssertNil(try vm.deletePet(), "档案不存在时再次删除应返回 nil")
    }
}
