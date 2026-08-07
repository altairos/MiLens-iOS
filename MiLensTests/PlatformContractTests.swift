import XCTest
@testable import MiLens

/// P1.4 平台适配层 mock 基础行为测试（对应源端 AdapterContract.test.ets）。
/// 覆盖 4 个 mock 的预设/查询/流式遍历/生命周期行为，确保后续 Service 测试可可靠注入。
final class PlatformContractTests: XCTestCase {

    // MARK: - MockPhotoLibraryAccess（对应源端 FakeMediaAccess）

    func testPhotoStreamVisitsAllAndReturnsCount() async throws {
        let assets = [
            PhotoAssetMetadata(identifier: "a", dateTaken: nil, pixelWidth: 100, pixelHeight: 100, fileSize: 10, displayName: "a.jpg"),
            PhotoAssetMetadata(identifier: "b", dateTaken: nil, pixelWidth: 100, pixelHeight: 100, fileSize: 10, displayName: "b.jpg"),
            PhotoAssetMetadata(identifier: "c", dateTaken: nil, pixelWidth: 100, pixelHeight: 100, fileSize: 10, displayName: "c.jpg")
        ]
        let access = MockPhotoLibraryAccess(assets: assets)

        var visited: [String] = []
        let count = try await access.streamPhotos { asset in
            visited.append(asset.identifier)
            return true
        }

        XCTAssertEqual(count, 3)
        XCTAssertEqual(visited, ["a", "b", "c"])
    }

    func testPhotoStreamStopsWhenConsumerReturnsFalse() async throws {
        let access = MockPhotoLibraryAccess(assets: [
            PhotoAssetMetadata(identifier: "a", dateTaken: nil, pixelWidth: 0, pixelHeight: 0, fileSize: 0, displayName: ""),
            PhotoAssetMetadata(identifier: "b", dateTaken: nil, pixelWidth: 0, pixelHeight: 0, fileSize: 0, displayName: ""),
            PhotoAssetMetadata(identifier: "c", dateTaken: nil, pixelWidth: 0, pixelHeight: 0, fileSize: 0, displayName: "")
        ])

        var visited = 0
        let count = try await access.streamPhotos { _ in
            visited += 1
            return visited < 2
        }

        XCTAssertEqual(count, 2)
        XCTAssertEqual(visited, 2)
    }

    func testPhotoCountAndMetadataLookup() async throws {
        let assets = [
            PhotoAssetMetadata(identifier: "uri_1", dateTaken: Date(timeIntervalSince1970: 1000), pixelWidth: 1080, pixelHeight: 1920, fileSize: 2048, displayName: "cat.jpg")
        ]
        let access = MockPhotoLibraryAccess(assets: assets)

        XCTAssertEqual(try await access.photoCount(), 1)

        let hit = try await access.metadata(forIdentifier: "uri_1")
        XCTAssertEqual(hit?.displayName, "cat.jpg")
        XCTAssertEqual(hit?.pixelWidth, 1080)

        let miss = try await access.metadata(forIdentifier: "nonexistent")
        XCTAssertNil(miss)
    }

    // MARK: - MockFileStorage（对应源端 FakeFileService）

    func testFileWriteThenReadRoundTrip() async throws {
        let fs = MockFileStorage()
        let data = Data([0x89, 0x50, 0x4E, 0x47])  // PNG header bytes
        try await fs.write(data, to: "/documents/test.png")

        let read = try await fs.read(at: "/documents/test.png")
        XCTAssertEqual(read, data)
    }

    func testFileCopyPreservesContent() async throws {
        let fs = MockFileStorage()
        fs.preset(Data("hello".utf8), at: "/tmp/src.txt")
        try await fs.copy(from: "/tmp/src.txt", to: "/documents/dest.txt")

        let read = try await fs.read(at: "/documents/dest.txt")
        XCTAssertEqual(String(data: read, encoding: .utf8), "hello")
    }

    func testFileReadNotFoundThrows() async throws {
        let fs = MockFileStorage()

        do {
            _ = try await fs.read(at: "/nonexistent")
            XCTFail("应抛出 fileNotFound")
        } catch let error as FileStorageError {
            XCTAssertEqual(error, .fileNotFound("/nonexistent"))
        }
    }

    func testFileExistsAndRemoveItem() async throws {
        let fs = MockFileStorage()
        try await fs.write(Data("test".utf8), to: "/cache/file.txt")
        XCTAssertTrue(fs.fileExists(at: "/cache/file.txt"))

        try await fs.removeItem(at: "/cache/file.txt")
        XCTAssertFalse(fs.fileExists(at: "/cache/file.txt"))
    }

    func testDirectoryCreateAndExists() async throws {
        let fs = MockFileStorage()
        XCTAssertFalse(fs.fileExists(at: "/documents/subdir"))

        try await fs.createDirectory(at: "/documents/subdir")
        XCTAssertTrue(fs.fileExists(at: "/documents/subdir"))
    }

    // MARK: - MockVisionService（对应源端 FakeVisionKit）

    func testVisionDetectReturnsPreset() async throws {
        let box = DetectionBox(x: 0.1, y: 0.2, width: 0.5, height: 0.6, label: "cat", confidence: 0.95)
        let vision = MockVisionService(detections: [box])

        let results = try await vision.detectPets(in: Data([0xFF]))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].label, "cat")
        XCTAssertEqual(results[0].confidence, 0.95, accuracy: 0.001)
    }

    func testVisionSegmentReturnsPreset() async throws {
        let mask = Data(repeating: 255, count: 4)
        let seg = SegmentationResult(mask: mask, bboxX: 0, bboxY: 0, bboxWidth: 2, bboxHeight: 2)
        let vision = MockVisionService(segmentation: seg)

        let result = try await vision.segmentSubject(in: Data([0xFF]))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.bboxWidth, 2)
        XCTAssertEqual(result?.mask.count, 4)
    }

    func testVisionSegmentReturnsNilWhenNotPreset() async throws {
        let vision = MockVisionService()
        let result = try await vision.segmentSubject(in: Data([0x00]))
        XCTAssertNil(result, "未预设分割结果时应返回 nil")
    }

    // MARK: - MockInferenceEngine（对应源端 FakeModelRunner）

    func testInferenceLifecycle() async throws {
        let engine = MockInferenceEngine()
        XCTAssertFalse(engine.isLoaded)

        try await engine.load(from: "/models/clip.mlmodel")
        XCTAssertTrue(engine.isLoaded)

        engine.release()
        XCTAssertFalse(engine.isLoaded)
    }

    func testInferencePredictReturnsPreset() async throws {
        let output = Data(repeating: 0, count: 512)  // 模拟 CLIP 512 维 float32
        let engine = MockInferenceEngine(outputs: [output])
        try await engine.load(from: "/models/test.mlmodel")

        let results = try await engine.predict([Data([0x01])])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].count, 512)
    }

    func testInferenceThrowsWhenNotLoaded() async throws {
        let engine = MockInferenceEngine()

        do {
            _ = try await engine.predict([Data([0x01])])
            XCTFail("未加载模型时 predict 应抛异常")
        } catch {
            // 预期：NSError domain "MockInferenceEngine"
        }
    }

    func testInferenceTensorInfos() {
        let inputInfo = TensorInfo(name: "input", shape: [1, 3, 224, 224], dataType: .float32)
        let outputInfo = TensorInfo(name: "embedding", shape: [1, 512], dataType: .float32)
        let engine = MockInferenceEngine(inputInfos: [inputInfo], outputInfos: [outputInfo])

        XCTAssertEqual(engine.inputInfos().count, 1)
        XCTAssertEqual(engine.inputInfos()[0].shape, [1, 3, 224, 224])
        XCTAssertEqual(engine.outputInfos()[0].dataType, .float32)
    }
}
