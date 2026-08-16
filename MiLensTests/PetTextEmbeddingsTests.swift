//  PetTextEmbeddingsTests —— 文本 embedding 加载测试。
//  覆盖真实资源加载（20 keys × 512 维布局与文件偏移对齐）、
//  fileNotFound（xctest bundle 无资源）、sizeMismatch（截断文件，关联值断言）。

import XCTest
@testable import MiLens

final class PetTextEmbeddingsTests: XCTestCase {

    func testLoadFromMainBundleReturnsFullTextSet() throws {
        // hosted 测试的 Bundle.main 即 app bundle，pet_text_embeddings.f32 随包分发。
        let set = try PetTextEmbeddings.load(from: .main)

        XCTAssertEqual(set.pet.count, petKeys.count)
        XCTAssertEqual(set.nonPet.count, nonPetKeys.count)
        for key in petKeys {
            XCTAssertEqual(set.pet[key]?.count, clipEmbeddingDim)
        }
        for key in nonPetKeys {
            XCTAssertEqual(set.nonPet[key]?.count, clipEmbeddingDim)
        }
        // 真实数据完整性冒烟：至少 cat 向量非全零。
        XCTAssertTrue(set.pet["cat"]?.contains { $0 != 0 } ?? false)
    }

    func testLoadedVectorsMatchFileLayout() throws {
        // 验证 key → 文件偏移切分：cat 在偏移 0，person 在第 11 个向量。
        let set = try PetTextEmbeddings.load(from: .main)
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "pet_text_embeddings", withExtension: "f32"))
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        XCTAssertEqual(
            data.count, (petKeys.count + nonPetKeys.count) * clipEmbeddingDim * 4)

        let floats = data.withUnsafeBytes { raw -> [Float] in
            Array(raw.bindMemory(to: Float.self))
        }
        XCTAssertEqual(set.pet["cat"], Array(floats[0..<clipEmbeddingDim]))
        let personStart = petKeys.count * clipEmbeddingDim
        XCTAssertEqual(
            set.nonPet["person"],
            Array(floats[personStart..<(personStart + clipEmbeddingDim)]))
    }

    func testLoadThrowsFileNotFoundInTestBundle() {
        // xctest bundle 内没有 .f32 资源。
        let testBundle = Bundle(for: PetTextEmbeddingsTests.self)
        do {
            _ = try PetTextEmbeddings.load(from: testBundle)
            XCTFail("应当抛出 fileNotFound")
        } catch let error as PetTextEmbeddingsError {
            XCTAssertEqual(error, .fileNotFound)
        } catch {
            XCTFail("期望 PetTextEmbeddingsError，实际 \(error)")
        }
    }

    func testLoadThrowsSizeMismatchForTruncatedFile() throws {
        // 4 字节假资源 → sizeMismatch(bytes: 4, expected: 40960)。
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PetTextEmbeddingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x41, 0x42, 0x43, 0x44]).write(
            to: dir.appendingPathComponent("pet_text_embeddings.f32"))

        let bundle = try XCTUnwrap(Bundle(path: dir.path))
        do {
            _ = try PetTextEmbeddings.load(from: bundle)
            XCTFail("应当抛出 sizeMismatch")
        } catch let error as PetTextEmbeddingsError {
            XCTAssertEqual(
                error, .sizeMismatch(bytes: 4, expected: 40960))
        } catch {
            XCTFail("期望 PetTextEmbeddingsError，实际 \(error)")
        }
    }
}