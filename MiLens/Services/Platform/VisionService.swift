//  VisionService —— Vision 框架适配协议（对应源端 IVisionKit）。
//  把 Vision（分类/主体分割）的直接调用隔离在此协议后面。
//  真实实现待 P1.5 AI 路线 ADR 定案后补；此处先定义协议骨架 + mock。
//  DESIGN.md §9 平台适配层。

import Foundation

/// 检测到的物体边界框（对应源端 DetectionBox，归一化坐标 0–1）。
struct DetectionBox: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let label: String
    let confidence: Double
}

/// 主体分割结果（对应源端 SegmentResult，裁去系统依赖的 PixelMap）。
struct SegmentationResult: Equatable, Sendable {
    /// Alpha 蒙版（0–255），长度 = bboxWidth × bboxHeight。
    let mask: Data
    let bboxX: Double
    let bboxY: Double
    let bboxWidth: Int
    let bboxHeight: Int
}

/// Vision 推理协议。
/// 输入为编码后的图片数据（JPEG/PNG），避免协议层引入 CoreGraphics 依赖。
/// 真实实现内部解码后调用 VNClassifyImageRequest / VNGenerateForegroundInstanceMask。
/// Sendable：实现类无共享可变状态（或单线程测试 mock），供后台执行器捕获。
protocol VisionService: Sendable {
    /// 检测图片中的宠物，返回边界框列表（对应源端 detectObjects）。
    func detectPets(in imageData: Data) async throws -> [DetectionBox]

    /// 主体分割，返回蒙版和裁切框。失败返回 nil（对应源端 segmentSubject）。
    func segmentSubject(in imageData: Data) async throws -> SegmentationResult?
}

// MARK: - Mock（对应源端 FakeVisionKit）

/// 预设检测/分割结果的 mock，用于单元测试。
final class MockVisionService: VisionService, @unchecked Sendable {
    /// 预设的检测结果（每次 detectPets 返回此列表的拷贝）。
    var presetDetections: [DetectionBox]
    /// 预设的分割结果（nil 模拟失败）。
    var presetSegmentation: SegmentationResult?

    init(detections: [DetectionBox] = [], segmentation: SegmentationResult? = nil) {
        self.presetDetections = detections
        self.presetSegmentation = segmentation
    }

    func detectPets(in imageData: Data) async throws -> [DetectionBox] {
        presetDetections
    }

    func segmentSubject(in imageData: Data) async throws -> SegmentationResult? {
        presetSegmentation
    }
}
