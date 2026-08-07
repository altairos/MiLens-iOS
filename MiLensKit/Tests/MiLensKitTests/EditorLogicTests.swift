import XCTest
@testable import MiLensKit

// 编辑器纯逻辑模块测试。源端无专门测试文件，按模块规格编写。

final class EditorColorAdjustTests: XCTestCase {

    func testNeutralIsZero() {
        XCTAssertTrue(isNeutral(NEUTRAL_EDITOR_ADJUSTMENTS))
        XCTAssertTrue(isNeutral(EditorColorAdjustments()))
    }

    func testNonNeutralIsNotZero() {
        XCTAssertFalse(isNeutral(EditorColorAdjustments(brightness: 1)))
        XCTAssertFalse(isNeutral(EditorColorAdjustments(sharpness: 1)))
    }

    func testClampAdjustments() {
        let over = EditorColorAdjustments(brightness: 200, contrast: -200, saturation: 50,
                                          temperature: 300, sharpness: -10)
        let clamped = clampAdjustments(over)
        XCTAssertEqual(clamped.brightness, 100)
        XCTAssertEqual(clamped.contrast, -100)
        XCTAssertEqual(clamped.saturation, 50)
        XCTAssertEqual(clamped.temperature, 100)
        XCTAssertEqual(clamped.sharpness, 0)
    }

    func testToFilterFactors() {
        // 0 → 1.0
        let neutral = toFilterFactors(EditorColorAdjustments())
        XCTAssertEqual(neutral.brightnessFactor, 1.0)
        XCTAssertEqual(neutral.contrastFactor, 1.0)
        XCTAssertEqual(neutral.saturationFactor, 1.0)

        // 100 → 1.8
        let boosted = toFilterFactors(EditorColorAdjustments(brightness: 100, contrast: 100, saturation: 100))
        XCTAssertEqual(boosted.brightnessFactor, 1.8, accuracy: 0.001)
        XCTAssertEqual(boosted.contrastFactor, 1.8, accuracy: 0.001)
        XCTAssertEqual(boosted.saturationFactor, 1.8, accuracy: 0.001)

        // -100 → 0.2
        let reduced = toFilterFactors(EditorColorAdjustments(brightness: -100))
        XCTAssertEqual(reduced.brightnessFactor, 0.2, accuracy: 0.001)
    }

    func testMergeAdjustments() {
        let base = EditorColorAdjustments(brightness: 10, contrast: 20, saturation: 30,
                                          temperature: 40, sharpness: 50)
        let delta = EditorColorAdjustDelta(brightness: 100, saturation: nil)
        let merged = mergeAdjustments(base: base, delta: delta)
        XCTAssertEqual(merged.brightness, 100)  // delta 覆盖
        XCTAssertEqual(merged.contrast, 20)     // base 保留
        XCTAssertEqual(merged.saturation, 30)   // base 保留
        XCTAssertEqual(merged.temperature, 40)  // base 保留
        XCTAssertEqual(merged.sharpness, 50)    // base 保留
    }
}

final class EditorSharpnessKernelTests: XCTestCase {

    func testStrengthZeroIsIdentity() {
        let kernel = buildSharpenKernel(strength: 0)
        XCTAssertEqual(kernel, [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0])
    }

    func testStrength50Standard() {
        let kernel = buildSharpenKernel(strength: 50)
        // amount = 1, center = 5, side = -1
        XCTAssertEqual(kernel, [0.0, -1.0, 0.0, -1.0, 5.0, -1.0, 0.0, -1.0, 0.0])
    }

    func testStrength100Strong() {
        let kernel = buildSharpenKernel(strength: 100)
        // amount = 2, center = 9, side = -2
        XCTAssertEqual(kernel, [0.0, -2.0, 0.0, -2.0, 9.0, -2.0, 0.0, -2.0, 0.0])
    }

    func testClampSharpness() {
        XCTAssertEqual(clampSharpness(-10), 0)
        XCTAssertEqual(clampSharpness(150), 100)
        XCTAssertEqual(clampSharpness(50), 50)
        XCTAssertTrue(clampSharpness(.nan).isFinite)
    }

    func testConvolveIdentityDoesNotChange() {
        let src: [UInt8] = [10, 20, 30, 255,  40, 50, 60, 255,
                            70, 80, 90, 255,  100, 110, 120, 255]
        let kernel = buildSharpenKernel(strength: 0)
        let out = convolveRgba(src: src, width: 2, height: 2, kernel: kernel)
        XCTAssertEqual(out, src)
    }

    func testConvolvePreservesAlpha() {
        let src: [UInt8] = [10, 20, 30, 128,  40, 50, 60, 200,
                            70, 80, 90, 0,    100, 110, 120, 255]
        let kernel = buildSharpenKernel(strength: 50)
        let out = convolveRgba(src: src, width: 2, height: 2, kernel: kernel)
        // Alpha 应原样保留
        XCTAssertEqual(out[3], 128)
        XCTAssertEqual(out[7], 200)
        XCTAssertEqual(out[11], 0)
        XCTAssertEqual(out[15], 255)
    }
}

final class EditorCropMathTests: XCTestCase {

    func testFullOverlap() {
        // 照片完全覆盖裁切框
        let input = EditorCropInput(photoX: 100, photoY: 100, photoW: 200, photoH: 200,
                                    cropX: 50, cropY: 50, cropW: 100, cropH: 100)
        let region = computeCropRegion(input: input)
        XCTAssertTrue(isCropRegionValid(region))
        // 裁切框(50,50)-(150,150) 映射到照片像素空间
        // 照片左上角 = (100-100, 100-100) = (0,0)
        // 交集左上 = (50,50) → 照片空间 (50,50)
        XCTAssertEqual(region.regionX, 50)
        XCTAssertEqual(region.regionY, 50)
        XCTAssertEqual(region.regionW, 100)
        XCTAssertEqual(region.regionH, 100)
    }

    func testNoOverlap() {
        let input = EditorCropInput(photoX: 0, photoY: 0, photoW: 100, photoH: 100,
                                    cropX: 200, cropY: 200, cropW: 50, cropH: 50)
        let region = computeCropRegion(input: input)
        XCTAssertEqual(region, ZERO_CROP_REGION)
        XCTAssertFalse(isCropRegionValid(region))
    }

    func testInvalidInput() {
        let input = EditorCropInput(photoX: 0, photoY: 0, photoW: 0, photoH: 100,
                                    cropX: 0, cropY: 0, cropW: 50, cropH: 50)
        XCTAssertEqual(computeCropRegion(input: input), ZERO_CROP_REGION)
    }
}

final class EditorLayerGeometryTests: XCTestCase {

    func testComputeLayerHalfSizeImageLayer() {
        let layer = EditorLayer(id: "test", type: .photo, scale: 2.0, width: 200, height: 100)
        let half = computeLayerHalfSize(layer)
        XCTAssertEqual(half.halfW, 200)  // 200 * 2.0 / 2
        XCTAssertEqual(half.halfH, 100)  // 100 * 2.0 / 2
    }

    func testComputeLayerHalfSizeTextLayer() {
        let layer = EditorLayer(id: "test", type: .text, scale: 1.0,
                                fontSize: 32, maxWidth: 400)
        let half = computeLayerHalfSize(layer)
        XCTAssertEqual(half.halfW, 200)  // 400 * 1.0 / 2
        XCTAssertEqual(half.halfH, 16)   // 32 * 1.0 / 2
    }

    func testIsPointInLayerNoRotation() {
        let layer = EditorLayer(id: "test", type: .photo, x: 100, y: 100,
                                scale: 1.0, width: 200, height: 200)
        XCTAssertTrue(isPointInLayer(layer, tapX: 100, tapY: 100))   // 中心
        XCTAssertTrue(isPointInLayer(layer, tapX: 199, tapY: 199))   // 边缘内
        XCTAssertFalse(isPointInLayer(layer, tapX: 250, tapY: 100))  // 外部
    }

    func testIsPointInLayerInvisible() {
        var layer = EditorLayer(id: "test", type: .photo, x: 100, y: 100,
                                scale: 1.0, width: 200, height: 200)
        layer.visible = false
        XCTAssertFalse(isPointInLayer(layer, tapX: 100, tapY: 100))
    }

    func testClampLayerScale() {
        XCTAssertEqual(clampLayerScale(0.05), MIN_LAYER_SCALE)
        XCTAssertEqual(clampLayerScale(10), MAX_LAYER_SCALE)
        XCTAssertEqual(clampLayerScale(2.5), 2.5)
        XCTAssertEqual(clampLayerScale(.nan), MIN_LAYER_SCALE)
    }

    func testSelectionBoxGeometryCorners() {
        // width=100, scale=2.0 → halfW = 100*2/2 = 100
        let layer = EditorLayer(id: "test", type: .photo, scale: 2.0, width: 100, height: 100)
        let geo = computeSelectionBoxGeometry(layer)
        XCTAssertEqual(geo.corners.count, 4)
        // 左上 (-100, -100), 右上 (100, -100), 右下 (100, 100), 左下 (-100, 100)
        XCTAssertEqual(geo.corners[0], [-100.0, -100.0])
        XCTAssertEqual(geo.corners[2], [100.0, 100.0])
    }

    func testPhotoExportRegionValid() {
        let layer = EditorLayer(id: "test", type: .photo, x: 200, y: 200,
                                scale: 1.0, width: 200, height: 200)
        let region = computePhotoExportRegion(photoLayer: layer, canvasW: 300, canvasH: 300)
        XCTAssertTrue(region.valid)
        // 照片左上 (100,100)，右下 (300,300)；画布 300×300
        // 交集 = (100,100)-(300,300)
        XCTAssertEqual(region.x, 100)
        XCTAssertEqual(region.y, 100)
        XCTAssertEqual(region.w, 200)
        XCTAssertEqual(region.h, 200)
    }

    func testPhotoExportRegionNoOverlap() {
        let layer = EditorLayer(id: "test", type: .photo, x: 500, y: 500,
                                scale: 1.0, width: 100, height: 100)
        let region = computePhotoExportRegion(photoLayer: layer, canvasW: 300, canvasH: 300)
        XCTAssertFalse(region.valid)
    }
}

final class EditorExifPolicyTests: XCTestCase {

    func testEmptySnapshot() {
        let snap = emptyExifSnapshot()
        XCTAssertEqual(snap.takenAt, "")
        XCTAssertEqual(snap.latitude, 0)
        XCTAssertEqual(snap.make, "")
    }

    func testResolveExifPolicyWithOriginalExif() {
        let snap = EditorExifSnapshot(takenAt: "2026:07:20 14:30:00", latitude: 40.5, longitude: -73.9)
        let policy = resolveExifPolicy(snapshot: snap, originalUri: "file://photo.jpg",
                                       nowIso: "2026-08-08T00:00:00.000Z")
        XCTAssertTrue(policy.preserveTakenAt)
        XCTAssertTrue(policy.hasOriginalExif)
        XCTAssertEqual(policy.resolvedOriginalUri, "file://photo.jpg")
        XCTAssertEqual(policy.resolvedLatitude, 40.5)
        XCTAssertEqual(policy.resolvedLongitude, -73.9)
        // takenAt 应被规范化（不为 nowIso）
        XCTAssertNotEqual(policy.resolvedTakenAt, "2026-08-08T00:00:00.000Z")
    }

    func testResolveExifPolicyWithoutExif() {
        let snap = emptyExifSnapshot()
        let policy = resolveExifPolicy(snapshot: snap, originalUri: "file://photo.jpg",
                                       nowIso: "2026-08-08T00:00:00.000Z")
        XCTAssertFalse(policy.preserveTakenAt)
        XCTAssertFalse(policy.hasOriginalExif)
        XCTAssertEqual(policy.resolvedTakenAt, "2026-08-08T00:00:00.000Z")
    }

    func testResolveExifPolicyWithoutOriginalUri() {
        // 有 EXIF 但无 originalUri → 不保留
        let snap = EditorExifSnapshot(takenAt: "2026:07:20 14:30:00")
        let policy = resolveExifPolicy(snapshot: snap, originalUri: "",
                                       nowIso: "2026-08-08T00:00:00.000Z")
        XCTAssertFalse(policy.preserveTakenAt)
        // hasOriginalExif 仍为 true（诊断标志）
        XCTAssertTrue(policy.hasOriginalExif)
        XCTAssertEqual(policy.resolvedTakenAt, "2026-08-08T00:00:00.000Z")
    }

    func testNormalizeExifDate() {
        let result = normalizeExifDate("2026:07:20 14:30:00")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.hasPrefix("2026-07-20T14:30:00"))
    }

    func testNormalizeExifDateEmpty() {
        XCTAssertEqual(normalizeExifDate(""), "")
        XCTAssertEqual(normalizeExifDate("   "), "")
    }

    func testNormalizeExifDateInvalid() {
        XCTAssertEqual(normalizeExifDate("not a date"), "")
    }

    func testParseExifGps() {
        let result = parseExifGps(rational: "40/1 42/1 5110/1000", ref: "N")
        XCTAssertEqual(result, 40 + 42.0/60 + 5.11/3600, accuracy: 0.0001)
    }

    func testParseExifGpsSouth() {
        let result = parseExifGps(rational: "40/1 0/1 0/1", ref: "S")
        XCTAssertEqual(result, -40.0, accuracy: 0.0001)
    }

    func testParseExifGpsEmpty() {
        XCTAssertEqual(parseExifGps(rational: "", ref: "N"), 0)
    }
}
