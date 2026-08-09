import Foundation

// PoseSimccDecoder — RTMPose 推理的纯逻辑边界：RGBA 预处理、SimCC 解码与脸框细化。
// 逐行翻译自源端 entry/.../services/PoseInferenceMath.ets（308 行），
// 与 PixelMap/MindSpore Lite/Core ML 解耦，便于主机单测覆盖模型契约（ADR-0007 §4.3）。
//
// 平台差异：源端 PixelMap 缓冲按 BGRA 解释（offsets [2,1,0]）；iOS 端
// decodeToRGBA 输出 RGBA（offsets [0,1,2]），其余数值逻辑完全一致。

/// pose 预处理的空间变换记录，供解码阶段把模型坐标映射回源图。
/// 对应源端 `PoseTransform`。
public struct PoseTransform: Equatable, Sendable {
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var cropX: Double
    public var cropY: Double
    public var cropSize: Double
    public var inputSize: Int

    public init(sourceWidth: Int, sourceHeight: Int, cropX: Double, cropY: Double,
                cropSize: Double, inputSize: Int) {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.cropX = cropX
        self.cropY = cropY
        self.cropSize = cropSize
        self.inputSize = inputSize
    }
}

/// pose 预处理结果：NCHW float32 数据 + 空间变换。
/// 对应源端 `PosePreprocessResult`。
public struct PosePreprocessResult: Sendable {
    public var data: [Float]
    public var transform: PoseTransform

    public init(data: [Float], transform: PoseTransform) {
        self.data = data
        self.transform = transform
    }
}

/// SimCC 输出对（simcc_x / simcc_y，按张量名绑定后的结果）。
/// 对应源端 `PoseOutputPair`。
public struct PoseOutputPair: Equatable, Sendable {
    public var simccX: [Float]
    public var simccY: [Float]

    public init(simccX: [Float], simccY: [Float]) {
        self.simccX = simccX
        self.simccY = simccY
    }
}

/// 三个稳定的脸部锚点：左眼、右眼和鼻子（固定顺序前三点）。
/// 对应源端 `hasStableFaceAnchors`。
public func hasStableFaceAnchors(_ pose: BeadPoseData, scoreThreshold: Double) -> Bool {
    pose.keypoints.count >= 3 &&
        pose.keypoints[0].confidence >= scoreThreshold &&
        pose.keypoints[1].confidence >= scoreThreshold &&
        pose.keypoints[2].confidence >= scoreThreshold
}

/// 从一次主体框粗推理的五官点估算紧凑脸框，供第二次 top-down 推理使用。
///
/// 只有双眼和鼻子均可信时才细化；否则返回 nil，调用方保留粗推理结果。
/// 这不是独立脸部检测器，而是避免新增模型时的保守 coarse-to-fine 适配。
/// 对应源端 `deriveFaceBoxFromPose`。
public func deriveFaceBoxFromPose(
    pose: BeadPoseData,
    sourceWidth: Int,
    sourceHeight: Int,
    subjectBox: CropRect,
    scoreThreshold: Double
) -> CropRect? {
    if sourceWidth <= 0 || sourceHeight <= 0 ||
        subjectBox.width <= 0 || subjectBox.height <= 0 ||
        !hasStableFaceAnchors(pose, scoreThreshold: scoreThreshold) {
        return nil
    }

    var minX = Double(sourceWidth)
    var minY = Double(sourceHeight)
    var maxX = -1.0
    var maxY = -1.0
    var visibleCount = 0
    let toleranceX = subjectBox.width * 0.08
    let toleranceY = subjectBox.height * 0.08
    for point in pose.keypoints {
        if point.confidence < scoreThreshold { continue }
        let x = point.x * Double(sourceWidth)
        let y = point.y * Double(sourceHeight)
        if !x.isFinite || !y.isFinite ||
            x < subjectBox.x - toleranceX ||
            x > subjectBox.x + subjectBox.width + toleranceX ||
            y < subjectBox.y - toleranceY ||
            y > subjectBox.y + subjectBox.height + toleranceY {
            return nil
        }
        minX = Swift.min(minX, x)
        minY = Swift.min(minY, y)
        maxX = Swift.max(maxX, x)
        maxY = Swift.max(maxY, y)
        visibleCount += 1
    }
    if visibleCount < 3 || maxX <= minX || maxY <= minY { return nil }

    let spanX = maxX - minX
    let spanY = maxY - minY
    // 五官外接框不含额头边缘和下颌：上/左右留 25%，鼻尖下方留 45%。
    let faceWidth = spanX * 1.5
    let faceHeight = spanY * 1.7
    var side = Swift.max(faceWidth, faceHeight)
    let subjectSide = Swift.max(subjectBox.width, subjectBox.height)
    if side < 16 || side >= subjectSide * 0.90 { return nil }
    side = Swift.min(side, Swift.min(Double(sourceWidth), Double(sourceHeight)))

    let centerX = (minX + maxX) / 2
    let centerY = (minY + maxY) / 2 + spanY * 0.10
    let x = Swift.max(0, Swift.min(Double(sourceWidth) - side, centerX - side / 2))
    let y = Swift.max(0, Swift.min(Double(sourceHeight) - side, centerY - side / 2))
    return CropRect(x: x, y: y, width: side, height: side)
}

/// 双线性采样单通道值（越界按 0 处理，与 OpenCV warp 默认一致）。
/// 对应源端 `sampleChannel`。
private func sampleChannel(
    _ rgba: [UInt8], width: Int, height: Int, x: Double, y: Double, channelOffset: Int
) -> Double {
    let x0 = Int(x.rounded(.down))
    let y0 = Int(y.rounded(.down))
    let x1 = x0 + 1
    let y1 = y0 + 1
    let fx = x - Double(x0)
    let fy = y - Double(y0)
    let p00 = x0 >= 0 && x0 < width && y0 >= 0 && y0 < height
        ? Double(rgba[(y0 * width + x0) * 4 + channelOffset]) : 0
    let p10 = x1 >= 0 && x1 < width && y0 >= 0 && y0 < height
        ? Double(rgba[(y0 * width + x1) * 4 + channelOffset]) : 0
    let p01 = x0 >= 0 && x0 < width && y1 >= 0 && y1 < height
        ? Double(rgba[(y1 * width + x0) * 4 + channelOffset]) : 0
    let p11 = x1 >= 0 && x1 < width && y1 >= 0 && y1 < height
        ? Double(rgba[(y1 * width + x1) * 4 + channelOffset]) : 0
    return p00 * (1 - fx) * (1 - fy) +
        p10 * fx * (1 - fy) +
        p01 * (1 - fx) * fy +
        p11 * fx * fy
}

/// 按训练配置的 top-down 方形仿射输入构造 NCHW 数据。
///
/// 输入为 iOS 解码的 RGBA 缓冲（top-left origin，与源端 PixelMap 契约对应）；
/// 裁框外区域与 OpenCV warp 默认一致填黑。归一化使用 ImageNet 统计
/// （mean=[0.485,0.456,0.406]，std=[0.229,0.224,0.225]，RTMPose 标准，非 CLIP）。
/// 对应源端 `preparePoseInput`。
public func preparePoseInput(
    rgba: [UInt8],
    sourceWidth: Int,
    sourceHeight: Int,
    bbox: CropRect,
    inputSize: Int,
    padding: Double = 1.25
) throws -> PosePreprocessResult {
    guard sourceWidth > 0, sourceHeight > 0, rgba.count == sourceWidth * sourceHeight * 4 else {
        throw PosePreprocessError.invalidBuffer
    }
    guard bbox.width > 0, bbox.height > 0, inputSize > 0, padding > 0 else {
        throw PosePreprocessError.invalidCrop
    }
    let centerX = bbox.x + bbox.width / 2
    let centerY = bbox.y + bbox.height / 2
    let cropSize = Swift.max(bbox.width, bbox.height) * padding
    let cropX = centerX - cropSize / 2
    let cropY = centerY - cropSize / 2
    let plane = inputSize * inputSize
    var data = [Float](repeating: 0, count: plane * 3)
    let means: [Double] = [0.485, 0.456, 0.406]
    let stds: [Double] = [0.229, 0.224, 0.225]
    // RGBA -> 模型 RGB；目标像素中心映射到源裁框（源端 BGRA 的 offsets 为 [2,1,0]）。
    let offsets: [Int] = [0, 1, 2]
    for y in 0..<inputSize {
        let sourceY = cropY + (Double(y) + 0.5) * cropSize / Double(inputSize) - 0.5
        for x in 0..<inputSize {
            let sourceX = cropX + (Double(x) + 0.5) * cropSize / Double(inputSize) - 0.5
            let destination = y * inputSize + x
            for channel in 0..<3 {
                let raw = sampleChannel(
                    rgba, width: sourceWidth, height: sourceHeight,
                    x: sourceX, y: sourceY, channelOffset: offsets[channel]) / 255
                data[channel * plane + destination] = Float((raw - means[channel]) / stds[channel])
            }
        }
    }
    return PosePreprocessResult(
        data: data,
        transform: PoseTransform(
            sourceWidth: sourceWidth, sourceHeight: sourceHeight,
            cropX: cropX, cropY: cropY, cropSize: cropSize, inputSize: inputSize))
}

/// pose 预处理错误。
public enum PosePreprocessError: Error, Equatable {
    case invalidBuffer
    case invalidCrop
}

private struct RawPeak {
    var index: Int
    var score: Double
}

private func rawArgmax(_ data: [Float], offset: Int, length: Int) -> RawPeak {
    var index = -1
    var score = -Double.infinity
    for i in 0..<length {
        let value = Double(data[offset + i])
        if value.isFinite && value > score {
            index = i
            score = value
        }
    }
    return RawPeak(index: index, score: score)
}

/// 按 MMPose SimCCLabel 契约解码：位置取原始峰值 argmax，
/// 置信度归一化为峰值 bin 的 softmax 概率（保持 [0,1] 语义，兼容下游阈值）。
///
/// 输出坐标为归一化 [0,1] 相对源图的比例坐标；无可信关键点时返回 nil。
/// 对应源端 `decodePoseOutputs`。
public func decodePoseOutputs(
    pair: PoseOutputPair,
    transform: PoseTransform,
    keypointCount: Int,
    simccLength: Int,
    splitRatio: Double,
    scoreThreshold: Double
) -> BeadPoseData? {
    var keypoints: [BeadPoseKeypoint] = []
    keypoints.reserveCapacity(keypointCount)
    var visibleCount = 0
    for keypoint in 0..<keypointCount {
        let offset = keypoint * simccLength
        let peakX = rawArgmax(pair.simccX, offset: offset, length: simccLength)
        let peakY = rawArgmax(pair.simccY, offset: offset, length: simccLength)
        guard peakX.index >= 0, peakY.index >= 0 else {
            keypoints.append(BeadPoseKeypoint(x: 0, y: 0, confidence: 0))
            continue
        }
        // 峰值 bin 的 softmax 概率：1 / (1 + (N-1)·exp(-s))，数值稳定且保持 [0,1] 语义
        let confX = 1 / (1 + (Double(simccLength) - 1) * exp(-peakX.score))
        let confY = 1 / (1 + (Double(simccLength) - 1) * exp(-peakY.score))
        let confidence = (confX * confY).squareRoot()
        guard confidence > 0 else {
            keypoints.append(BeadPoseKeypoint(x: 0, y: 0, confidence: 0))
            continue
        }
        let inputX = Double(peakX.index) / splitRatio
        let inputY = Double(peakY.index) / splitRatio
        let sourceX = transform.cropX + inputX * transform.cropSize / Double(transform.inputSize)
        let sourceY = transform.cropY + inputY * transform.cropSize / Double(transform.inputSize)
        let normalizedX = Swift.max(0, Swift.min(1, sourceX / Double(transform.sourceWidth)))
        let normalizedY = Swift.max(0, Swift.min(1, sourceY / Double(transform.sourceHeight)))
        keypoints.append(BeadPoseKeypoint(x: normalizedX, y: normalizedY, confidence: confidence))
        if confidence >= scoreThreshold { visibleCount += 1 }
    }
    return visibleCount > 0 ? BeadPoseData(keypoints: keypoints) : nil
}
