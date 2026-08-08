//  PetTextEmbeddings —— CLIP 文本侧预计算 embedding 加载（对应源端 services/PetTextEmbeddings.ets）。
//
//  DESIGN.md §4：Service 负责 IO + 异常处理。
//  从 bundle 加载 pet_text_embeddings.f32（20 keys × 512 维 × float32 = 40960 字节），
//  解码为 pet / nonPet 两组 [String: [Float]] 字典，供 AiInferenceLogic.classifyImageEmbedding 使用。
//
//  文件布局（与源端 generate_clip_embeddings.py 一致）：
//    [0 ..  9]×512 : petKeys 顺序（cat, kitten, dog, ... pet）
//    [10 .. 19]×512: nonPetKeys 顺序（person, car, ... document）
//
//  speciesLabels 是 UI 文案，保留在源代码中（非生成数据）。

import Foundation

/// CLIP embedding 维度（ViT-B/32，对应源端 `EMBEDDING_DIM`）。
let clipEmbeddingDim = 512

/// 文本 embedding 原始资源文件名（对应源端 `EMBEDDING_FILE`）。
private let embeddingFile = "pet_text_embeddings"

/// 宠物标签 key（顺序与 .f32 文件前 10 个向量一致，对应源端 `PET_KEYS`）。
let petKeys: [String] = [
    "cat", "kitten", "dog", "puppy", "rabbit",
    "hamster", "bird", "fish", "turtle", "pet",
]

/// 非宠物标签 key（顺序与 .f32 文件后 10 个向量一致，对应源端 `NON_PET_KEYS`）。
let nonPetKeys: [String] = [
    "person", "car", "building", "food", "plant",
    "flower", "furniture", "sky", "water", "document",
]

/// 物种标签可读名称（简体中文 UI 文案，对应源端 `PET_SPECIES_LABELS`）。
/// "pet" 是泛化 key，不映射到具体物种（classifyImageEmbedding 中 species 取 bestPet.key）。
let petSpeciesLabels: [String: String] = [
    "cat": "猫",
    "kitten": "小猫",
    "dog": "狗",
    "puppy": "小狗",
    "rabbit": "兔子",
    "hamster": "仓鼠",
    "bird": "鸟",
    "fish": "鱼",
    "turtle": "龟",
]

/// CLIP 文本 embedding 集合（对应源端 `TextEmbeddingSet`）。
struct PetTextEmbeddingSet: Equatable {
    let pet: [String: [Float]]
    let nonPet: [String: [Float]]
}

/// 文本 embedding 加载错误。
enum PetTextEmbeddingsError: Error, Equatable {
    case fileNotFound
    case sizeMismatch(bytes: Int, expected: Int)
}

/// CLIP 文本 embedding 加载器（对应源端 `loadPetTextEmbeddings`）。
enum PetTextEmbeddings {

    /// 从 bundle 加载 pet_text_embeddings.f32 并解码为两组字典。
    /// - Parameter bundle: 资源所在 bundle（默认 .main）。
    /// - Throws: 文件缺失或大小不符时抛出 `PetTextEmbeddingsError`。
    static func load(from bundle: Bundle = .main) throws -> PetTextEmbeddingSet {
        guard let url = bundle.url(forResource: embeddingFile, withExtension: "f32") else {
            throw PetTextEmbeddingsError.fileNotFound
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])

        let totalKeys = petKeys.count + nonPetKeys.count
        let expectedBytes = totalKeys * clipEmbeddingDim * MemoryLayout<Float>.size
        guard data.count == expectedBytes else {
            throw PetTextEmbeddingsError.sizeMismatch(bytes: data.count, expected: expectedBytes)
        }

        // 整体解码为 [Float]（float32 小端序，与 generate_clip_embeddings.py 输出一致）
        var values = [Float](repeating: 0, count: totalKeys * clipEmbeddingDim)
        data.withUnsafeBytes { rawBuffer in
            let floatPtr = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<values.count {
                values[i] = floatPtr[i]
            }
        }

        let pet = takeVectors(values, keys: petKeys, start: 0)
        let nonPet = takeVectors(values, keys: nonPetKeys, start: petKeys.count * clipEmbeddingDim)

        return PetTextEmbeddingSet(pet: pet, nonPet: nonPet)
    }

    /// 从连续 Float 数组中按 key 顺序切分出字典（对应源端 `takeVectors`）。
    private static func takeVectors(
        _ values: [Float], keys: [String], start: Int
    ) -> [String: [Float]] {
        var result: [String: [Float]] = [:]
        for (i, key) in keys.enumerated() {
            let offset = start + i * clipEmbeddingDim
            result[key] = Array(values[offset..<(offset + clipEmbeddingDim)])
        }
        return result
    }
}
