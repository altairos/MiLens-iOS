//  IOSVisionService —— VisionService 真实实现（对应源端 adapters/impl/VisionKitImpl.ets）。
//
//  把 Vision 框架（VNClassifyImageRequest / VNGenerateForegroundInstanceMask）的直接调用
//  隔离在 VisionService 协议后面。
//
//  ADR-0007 §2.1/§3.2：
//  - detectPets：VNClassifyImageRequest（系统分类）做宠物预筛，匹配动物相关 ImageNet 标签。
//    这是 Phase 1 快速过滤；Phase 2 由 CLIP（ClipInferenceService）精确分类。
//  - segmentSubject：VNGenerateForegroundInstanceMask（iOS 17+）做主体分割，对应源端 subjectSegmentation。
//
//  降级：解码失败 / Vision 不可用时返回空结果（[] / nil），不抛错中断扫描流程（对应源端 catch 返回空）。
//  真实模型质量需 iPhone 真机验证（AGENTS.md §5）。

import CoreGraphics
import CoreVideo
import ImageIO
import Vision
import Foundation

/// VisionService 的 Vision 框架真实实现（对应源端 `VisionKitImpl`）。
///
/// - detectPets：VNClassifyImageRequest 系统分类 → 宠物标签匹配（无定位，返回全图 bbox）。
/// - segmentSubject：VNGenerateForegroundInstanceMask（iOS 17+）→ 前景 alpha 蒙版。
final class IOSVisionService: VisionService {

    /// VNClassifyImageRequest 的最低置信度阈值（低于此值忽略，对应扫描预筛宽松度）。
    private let classificationThreshold: Float = 0.3

    func detectPets(in imageData: Data) async throws -> [DetectionBox] {
        guard let cgImage = Self.decode(imageData) else { return [] }
        return try Self.classifyPet(cgImage: cgImage, threshold: classificationThreshold)
    }

    func segmentSubject(in imageData: Data) async throws -> SegmentationResult? {
        guard let cgImage = Self.decode(imageData) else { return nil }
        return try Self.generateForegroundMask(cgImage: cgImage)
    }

    // MARK: - 宠物分类（VNClassifyImageRequest）

    /// ImageNet 标签中与宠物/动物相关的关键词（小写匹配）。
    /// 涵盖常见物种 + 犬品种后缀（ImageNet 含 ~120 个犬品种，多数标签不含 "dog"）。
    /// 这是 Phase 1 预筛，宽松匹配（宁多收）；Phase 2 CLIP 精确分类。
    private static let petKeywords: Set<String> = [
        // 核心物种
        "cat", "dog", "puppy", "kitten", "kitty",
        "bird", "fish", "rabbit", "hare", "hamster",
        "turtle", "tortoise", "guinea pig", "parrot", "canary",
        // 犬品种常见后缀（ImageNet 大量品种标签不含 "dog"）
        "retriever", "poodle", "terrier", "spaniel",
        "shepherd", "collie", "mastiff", "corgi",
        "beagle", "dalmatian", "boxer", "schnauzer",
        "chow", "pug", "malamute", "husky",
    ]

    /// 执行 VNClassifyImageRequest，匹配宠物标签。
    private static func classifyPet(cgImage: CGImage, threshold: Float) throws -> [DetectionBox] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }

        // 过滤置信度 + 宠物标签匹配，取最高分
        // VNClassificationObservation 只有 identifier（无单独 label），用 identifier 做关键词匹配。
        let petMatches = observations.filter { obs in
            obs.confidence >= threshold && isPetLabel(obs.identifier)
        }

        guard let best = petMatches.max(by: { $0.confidence < $1.confidence }) else {
            return []
        }

        // VNClassifyImageRequest 是整图分类，无定位 → 返回全图 bbox（归一化 0..1）
        return [DetectionBox(
            x: 0, y: 0, width: 1, height: 1,
            label: best.identifier,
            confidence: Double(best.confidence)
        )]
    }

    /// 判断 ImageNet 标签是否与宠物/动物相关（小写子串匹配关键词）。
    private static func isPetLabel(_ identifier: String) -> Bool {
        let lowerId = identifier.lowercased()
        for keyword in petKeywords {
            if lowerId.contains(keyword) {
                return true
            }
        }
        return false
    }

    // MARK: - 主体分割（VNGenerateForegroundInstanceMask，iOS 17+）

    /// 执行 VNGenerateForegroundInstanceMaskRequest，提取前景 alpha 蒙版。
    private static func generateForegroundMask(cgImage: CGImage) throws -> SegmentationResult? {
        guard #available(iOS 17.0, *) else { return nil }

        let maskRequest = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([maskRequest])

        guard let observation = maskRequest.results?.first else { return nil }

        // 生成与原图尺寸一致的缩放蒙版
        let scaledMask = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances, from: handler)

        let width = CVPixelBufferGetWidth(scaledMask)
        let height = CVPixelBufferGetHeight(scaledMask)
        guard width > 0, height > 0 else { return nil }

        guard let alpha = extractAlphaMask(from: scaledMask, width: width, height: height) else {
            return nil
        }

        return SegmentationResult(
            mask: alpha,
            bboxX: 0, bboxY: 0,
            bboxWidth: width, bboxHeight: height
        )
    }

    /// 从 CVPixelBuffer 提取 0–255 的 alpha 蒙版（处理 float32 / 8-bit 单通道格式）。
    private static func extractAlphaMask(
        from pixelBuffer: CVPixelBuffer, width: Int, height: Int
    ) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        var alpha = Data(count: width * height)
        alpha.withUnsafeMutableBytes { rawBuffer in
            let out = rawBuffer.bindMemory(to: UInt8.self)

            switch pixelFormat {
            case kCVPixelFormatType_OneComponent8:
                // 8-bit 单通道（0-255）
                let src = baseAddress.assumingMemoryBound(to: UInt8.self)
                for y in 0..<height {
                    for x in 0..<width {
                        out[y * width + x] = src[y * bytesPerRow + x]
                    }
                }
            case kCVPixelFormatType_OneComponent32Float:
                // float32 单通道（0.0-1.0 置信度）
                let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size
                let src = baseAddress.assumingMemoryBound(to: Float32.self)
                for y in 0..<height {
                    for x in 0..<width {
                        let value = src[y * floatsPerRow + x]
                        let clamped = max(0, min(1, value))
                        out[y * width + x] = UInt8(clamped * 255)
                    }
                }
            default:
                // 未知格式：蒙版留零（调用方降级处理）
                break
            }
        }
        return alpha
    }

    // MARK: - 图像解码（复用 ImageAnalyzer 的解码逻辑）

    /// 从编码图片数据（JPEG/PNG）解码为 CGImage。失败返回 nil。
    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
