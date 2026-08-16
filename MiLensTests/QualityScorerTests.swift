//  QualityScorerTests —— 质量评分 + 重复分组编排测试
//  对应源端 QualityScorer 行为（in-memory SwiftData + mock 平台服务）。

import XCTest
import SwiftData
@testable import MiLens

@MainActor
final class QualityScorerTests: XCTestCase {

    // MARK: - 辅助

    private func makeScorer(
        sharpness: Double = 3000,
        phash: String? = "0000000000000000"
    ) -> (QualityScorer, SwiftDataPhotoRepository, MockFileStorage, MockImageAnalyzer, ModelContainer) {
        // container 必须返回并持有——mainContext 不持有 container，
        // 局部变量释放后 repo 的 fetch 触发 SwiftData 内部 SIGTRAP（悬垂引用）。
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let fileStorage = MockFileStorage()
        let analyzer = MockImageAnalyzer()
        analyzer.sharpnessResult = sharpness
        analyzer.phashResult = phash
        let scorer = QualityScorer(
            photoRepo: photoRepo, imageAnalyzer: analyzer, fileStorage: fileStorage)
        return (scorer, photoRepo, fileStorage, analyzer, container)
    }

    /// 插入一张 pending 照片（qualityScore == 0）并预设其文件数据。
    @discardableResult
    private func insertPending(
        into repo: SwiftDataPhotoRepository, fileStorage: MockFileStorage,
        uri: String = "/documents/a.jpg", width: Int = 1920, height: Int = 1080,
        phash: String = ""
    ) throws -> Photo {
        let photo = Photo(uri: uri, originalURI: uri, width: width, height: height,
                          fileSize: 2048, phash: phash, qualityScore: 0)
        try repo.insertPhoto(photo)
        fileStorage.preset(Data([0xFF, 0xD8, 0xFF]), at: uri)
        return photo
    }

    // MARK: - computeAllQualityScores

    func testComputeScoresForPendingPhotos() async throws {
        let (scorer, repo, fs, _, container) = makeScorer(sharpness: 3000)
        try insertPending(into: repo, fileStorage: fs)
        try insertPending(into: repo, fileStorage: fs, uri: "/documents/b.jpg")

        let computed = await scorer.computeAllQualityScores()
        XCTAssertEqual(computed, 2)

        let photos = try repo.getPhotosPage(offset: 0, limit: 10)
        for p in photos {
            XCTAssertGreaterThan(p.qualityScore, 0)
            XCTAssertEqual(p.sharpness, 3000)
        }
    }

    func testSkipsPhotoWithEmptyURI() async throws {
        let (scorer, repo, fs, _, container) = makeScorer()
        // qualityScore=0 但 uri 为空 → 跳过
        let photo = Photo(uri: "", originalURI: "x", qualityScore: 0)
        try repo.insertPhoto(photo)

        let computed = await scorer.computeAllQualityScores()
        XCTAssertEqual(computed, 0)
    }

    func testSkipsPhotoWhenFileReadFails() async throws {
        let (scorer, repo, fs, _, container) = makeScorer()
        // 插入但**不**预设文件数据 → read 抛错 → 跳过
        let photo = Photo(uri: "/missing.jpg", originalURI: "/missing.jpg", qualityScore: 0)
        try repo.insertPhoto(photo)

        let computed = await scorer.computeAllQualityScores()
        XCTAssertEqual(computed, 0)
    }

    func testFillsPHashWhenMissing() async throws {
        let (scorer, repo, fs, analyzer, container) = makeScorer(phash: "abcdef0123456789")
        try insertPending(into: repo, fileStorage: fs) // phash 初始为空

        _ = await scorer.computeAllQualityScores()
        XCTAssertEqual(analyzer.phashCalls.count, 1)

        let photos = try repo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos[0].phash, "abcdef0123456789")
    }

    func testDoesNotRecomputeExistingPHash() async throws {
        let (scorer, repo, fs, analyzer, container) = makeScorer(phash: "ffffffffffffffff")
        try insertPending(into: repo, fileStorage: fs, phash: "1122334455667788")

        _ = await scorer.computeAllQualityScores()
        // 已有 phash → 不调用 computePHash
        XCTAssertEqual(analyzer.phashCalls.count, 0)
    }

    // MARK: - findDuplicates

    func testFindDuplicatesGroupsSimilarPhotos() async throws {
        let (scorer, repo, fs, _, container) = makeScorer()
        // 两张相似 pHash（距离 ≤ 8）
        let a = try insertPending(into: repo, fileStorage: fs, uri: "/a.jpg", phash: "0000000000000000")
        _ = try insertPending(into: repo, fileStorage: fs, uri: "/b.jpg", phash: "0000000000000001")
        // 先评分（让 qualityScore 非零，否则不进入候选差异判断）
        try repo.updateQualityData(a, sharpness: 5000, qualityScore: 0.9, phash: "0000000000000000")

        let groupCount = await scorer.findDuplicates()
        XCTAssertEqual(groupCount, 1)

        let photos = try repo.getPhotosPage(offset: 0, limit: 10)
        let bests = photos.filter(\.isBest)
        let dups = photos.filter { !$0.isBest }
        XCTAssertEqual(bests.count, 1)
        XCTAssertEqual(dups.count, 1)
        XCTAssertNotNil(dups.first?.duplicateOf)
    }

    func testFindDuplicatesReturnsZeroWhenNoCandidates() async throws {
        let (scorer, repo, fs, _, container) = makeScorer()
        // 无 phash 的照片 → 无候选
        try insertPending(into: repo, fileStorage: fs, phash: "")

        let groupCount = await scorer.findDuplicates()
        XCTAssertEqual(groupCount, 0)
    }

    // MARK: - runPostScanAnalysis

    func testPostScanAnalysisScoresThenGroups() async throws {
        let (scorer, repo, fs, _, container) = makeScorer(sharpness: 4000, phash: "0000000000000000")
        try insertPending(into: repo, fileStorage: fs, uri: "/a.jpg")
        try insertPending(into: repo, fileStorage: fs, uri: "/b.jpg")

        await scorer.runPostScanAnalysis()

        let photos = try repo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 2)
        // 评分后 qualityScore 应非零
        for p in photos { XCTAssertGreaterThan(p.qualityScore, 0) }
    }

    // MARK: - 仓储错误降级（wrapper 注入失败）

    private func makeFailingScorer() -> (
        QualityScorer, SwiftDataPhotoRepository, MockFileStorage,
        MockImageAnalyzer, ModelContainer, QualityFailurePhotoRepository
    ) {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let failing = QualityFailurePhotoRepository(base: photoRepo)
        let fileStorage = MockFileStorage()
        let analyzer = MockImageAnalyzer()
        analyzer.sharpnessResult = 3000
        analyzer.phashResult = "0000000000000000"
        let scorer = QualityScorer(
            photoRepo: failing, imageAnalyzer: analyzer, fileStorage: fileStorage)
        return (scorer, photoRepo, fileStorage, analyzer, container, failing)
    }

    func testComputeScoresReturnsZeroWhenPendingFetchFails() async throws {
        let (scorer, repo, fs, _, _, failing) = makeFailingScorer()
        try insertPending(into: repo, fileStorage: fs)
        failing.failGetPending = true

        let computed = await scorer.computeAllQualityScores()
        XCTAssertEqual(computed, 0)
    }

    func testFindDuplicatesReturnsZeroWhenCandidatesFetchFails() async throws {
        let (scorer, repo, fs, _, _, failing) = makeFailingScorer()
        let a = try insertPending(into: repo, fileStorage: fs, uri: "/a.jpg", phash: "0000000000000000")
        _ = try insertPending(into: repo, fileStorage: fs, uri: "/b.jpg", phash: "0000000000000001")
        try repo.updateQualityData(a, sharpness: 5000, qualityScore: 0.9, phash: "0000000000000000")
        failing.failGetCandidates = true

        let groupCount = await scorer.findDuplicates()
        XCTAssertEqual(groupCount, 0)
    }

    func testFindDuplicatesStillReturnsGroupsWhenMarksWriteFails() async throws {
        let (scorer, repo, fs, _, _, failing) = makeFailingScorer()
        let a = try insertPending(into: repo, fileStorage: fs, uri: "/a.jpg", phash: "0000000000000000")
        _ = try insertPending(into: repo, fileStorage: fs, uri: "/b.jpg", phash: "0000000000000001")
        try repo.updateQualityData(a, sharpness: 5000, qualityScore: 0.9, phash: "0000000000000000")
        failing.failReplaceMarks = true

        // 分组已完成、仅落库失败 → 仍返回组数（对应源端告警不中断）。
        let groupCount = await scorer.findDuplicates()
        XCTAssertEqual(groupCount, 1)

        // 落库未发生：照片保持默认 isBest=true、duplicateOf=nil。
        let photos = try repo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 2)
        for p in photos {
            XCTAssertTrue(p.isBest)
            XCTAssertNil(p.duplicateOf)
        }
    }
}

// MARK: - 失败注入仓储（包装真实 SwiftData repo，仅 QualityScorer 三个读写点可注入失败）

@MainActor
final class QualityFailurePhotoRepository: PhotoRepositoryProtocol {
    private let base: SwiftDataPhotoRepository
    /// getPendingQualityScorePhotos 抛错。
    var failGetPending = false
    /// getDuplicateCandidates 抛错。
    var failGetCandidates = false
    /// replaceDuplicateMarks 抛错（分组完成但落库失败）。
    var failReplaceMarks = false

    init(base: SwiftDataPhotoRepository) {
        self.base = base
    }

    func getPhoto(id: UUID) throws -> Photo? { try base.getPhoto(id: id) }
    func getPhotoByURI(_ uri: String) throws -> Photo? { try base.getPhotoByURI(uri) }
    func getPhotoByOriginalURI(_ originalURI: String) throws -> Photo? {
        try base.getPhotoByOriginalURI(originalURI)
    }
    func getAllOriginalURIs() throws -> Set<String> { try base.getAllOriginalURIs() }
    func getAllPhotoURIs() throws -> Set<String> { try base.getAllPhotoURIs() }
    func countAllPhotos() throws -> Int { try base.countAllPhotos() }
    func getLatestPhotoDate() throws -> Date? { try base.getLatestPhotoDate() }
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] {
        try base.getPhotosPage(offset: offset, limit: limit)
    }
    func getPhotosByPet(_ pet: Pet) throws -> [Photo] { try base.getPhotosByPet(pet) }
    func getUnassignedPhotos(limit: Int) throws -> [Photo] {
        try base.getUnassignedPhotos(limit: limit)
    }
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo] {
        try base.getAnniversaryPhotos(month: month, day: day, excludeYear: excludeYear)
    }
    func insertPhoto(_ photo: Photo) throws { try base.insertPhoto(photo) }
    func insertPhotos(_ photos: [Photo]) throws { try base.insertPhotos(photos) }
    func deletePhoto(_ photo: Photo) throws { try base.deletePhoto(photo) }
    func updatePhoto(_ photo: Photo) throws { try base.updatePhoto(photo) }
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws { try base.assignPhoto(photo, to: pet) }
    func batchAssignPhotos(_ photos: [Photo], to targetPet: Pet?) throws -> [Pet] {
        try base.batchAssignPhotos(photos, to: targetPet)
    }
    func setFavorite(_ photo: Photo, favorite: Bool) throws {
        try base.setFavorite(photo, favorite: favorite)
    }
    func updateNote(_ photo: Photo, note: String) throws {
        try base.updateNote(photo, note: note)
    }
    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo] {
        guard !failGetPending else { throw PhotoRepositoryFailure() }
        return try base.getPendingQualityScorePhotos(limit: limit)
    }
    func getDuplicateCandidates() throws -> [Photo] {
        guard !failGetCandidates else { throw PhotoRepositoryFailure() }
        return try base.getDuplicateCandidates()
    }
    func updateQualityData(
        _ photo: Photo, sharpness: Double, qualityScore: Double, phash: String
    ) throws {
        try base.updateQualityData(
            photo, sharpness: sharpness, qualityScore: qualityScore, phash: phash)
    }
    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws {
        guard !failReplaceMarks else { throw PhotoRepositoryFailure() }
        try base.replaceDuplicateMarks(groups)
    }
}
