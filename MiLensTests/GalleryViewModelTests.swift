import XCTest
@testable import MiLens

/// GalleryViewModel 测试——扫描增量游标保存条件（P0 续）。
/// 只有「真正完整完成」的扫描（未取消且无错误）才允许保存游标；
/// 失败/取消时保存会导致下次增量扫描跳过本次未扫到的照片。
/// 使用内存仓储 + MockPhotoLibraryAccess 失败注入 + MockScanCursorStore 记录保存。
@MainActor
final class GalleryViewModelTests: XCTestCase {

    private func makeVM(
        library: MockPhotoLibraryAccess,
        cursorStore: MockScanCursorStore = MockScanCursorStore()
    ) -> GalleryViewModel {
        GalleryViewModel(
            photoRepo: InMemoryPhotoRepository(),
            petRepo: InMemoryPetRepository(),
            photoLibrary: library,
            vision: MockVisionService(),
            fileStorage: MockFileStorage(),
            sandboxDir: "/documents/MiPhotos",
            cursorStore: cursorStore
        )
    }

    /// 等待扫描 Task 结束（isScanning 复位为 false）。
    private func waitForScanToFinish(_ vm: GalleryViewModel) async {
        for _ in 0..<200 where vm.isScanning {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(vm.isScanning, "扫描应在超时前结束")
    }

    // MARK: - 游标保存条件

    func testFailedScanDoesNotSaveCursor() async {
        let library = MockPhotoLibraryAccess(assets: [])
        library.streamError = GalleryTestError.streamFailure
        let cursorStore = MockScanCursorStore()
        let vm = makeVM(library: library, cursorStore: cursorStore)

        vm.startScan(scanNewOnly: true)
        await waitForScanToFinish(vm)

        XCTAssertTrue(vm.scanFailed)
        XCTAssertTrue(vm.showScanCompleteDialog) // 失败也弹窗展示错误信息
        XCTAssertTrue(cursorStore.savedTimestamps.isEmpty, "失败扫描不得保存增量游标")
    }

    func testSuccessfulScanSavesCursor() async {
        let library = MockPhotoLibraryAccess(assets: [])
        let cursorStore = MockScanCursorStore()
        let vm = makeVM(library: library, cursorStore: cursorStore)

        vm.startScan(scanNewOnly: true)
        await waitForScanToFinish(vm)

        XCTAssertFalse(vm.scanFailed)
        XCTAssertEqual(cursorStore.savedTimestamps.count, 1, "完整完成的扫描应保存游标")
    }

    func testScanNewOnlyKeepsBaselineUntilNextSuccess() async {
        // 已有历史游标：本次失败不覆盖，lastSuccessfulScan 保持原值
        let baseline = Date(timeIntervalSince1970: 1000)
        let cursorStore = MockScanCursorStore(lastSuccessfulScan: baseline)
        let library = MockPhotoLibraryAccess(assets: [])
        library.photoCountError = GalleryTestError.countFailure
        let vm = makeVM(library: library, cursorStore: cursorStore)

        vm.startScan(scanNewOnly: true)
        await waitForScanToFinish(vm)

        XCTAssertTrue(vm.scanFailed)
        XCTAssertEqual(cursorStore.savedTimestamps.count, 0)
        XCTAssertEqual(cursorStore.lastSuccessfulScan, baseline, "失败扫描不得覆盖历史游标")
    }
}

/// 测试用错误。
private enum GalleryTestError: Error {
    case streamFailure
    case countFailure
}

// MARK: - 内存 mock

/// 内存照片仓储（GalleryViewModel 测试用）。
@MainActor
private final class InMemoryPhotoRepository: PhotoRepositoryProtocol {
    private var photos: [Photo] = []

    func getPhoto(id: UUID) throws -> Photo? { photos.first { $0.id == id } }
    func getPhotoByURI(_ uri: String) throws -> Photo? { photos.first { $0.uri == uri } }
    func getPhotoByOriginalURI(_ originalURI: String) throws -> Photo? { photos.first { $0.originalURI == originalURI } }
    func getAllOriginalURIs() throws -> Set<String> { Set(photos.map(\.originalURI)) }
    func getAllPhotoURIs() throws -> Set<String> { Set(photos.map(\.uri)) }
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] {
        Array(photos.sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }.dropFirst(offset).prefix(limit))
    }
    func getPhotosByPet(_ pet: Pet) throws -> [Photo] { photos.filter { $0.pet?.id == pet.id } }
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo] { [] }
    func insertPhoto(_ photo: Photo) throws { photos.append(photo) }
    func deletePhoto(_ photo: Photo) throws { photos.removeAll { $0.id == photo.id } }
    func updatePhoto(_ photo: Photo) throws {}
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws { photo.pet = pet }
    func setFavorite(_ photo: Photo, favorite: Bool) throws { photo.isFavorite = favorite }
    func updateNote(_ photo: Photo, note: String) throws { photo.note = note }
    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo] { [] }
    func getDuplicateCandidates() throws -> [Photo] { [] }
    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws {}
    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws {}
}

/// 内存宠物仓储（GalleryViewModel 测试用）。
@MainActor
private final class InMemoryPetRepository: PetRepositoryProtocol {
    private var pets: [Pet] = []

    func getAllPets() throws -> [Pet] { pets }
    func getPet(id: UUID) throws -> Pet? { pets.first { $0.id == id } }
    func insertPet(_ pet: Pet) throws { pets.append(pet) }
    func updatePet(_ pet: Pet) throws {}
    func deletePet(_ pet: Pet) throws { pets.removeAll { $0.id == pet.id } }
    func refreshPhotoCount(for pet: Pet) throws {}
    func updateFeatureData(_ pet: Pet, data: Data?) throws {}
}
