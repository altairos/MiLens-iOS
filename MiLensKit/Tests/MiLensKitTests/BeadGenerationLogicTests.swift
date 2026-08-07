import XCTest
@testable import MiLensKit

/// BeadGenerationLogic 测试。逐条翻译自源端 entry/.../test/BeadGenerationViewModel.test.ets。
final class BeadGenerationLogicTests: XCTestCase {

    // MARK: - computeSubjectFromBBox

    func testComputeSubjectFromBBoxReturnsNilForZeroAreaBox() {
        let result = computeSubjectFromBBox(box: CropRect(x: 0, y: 0, width: 0, height: 0), w: 100, h: 100)
        XCTAssertNil(result)
    }

    func testComputeSubjectFromBBoxReturnsSubjectWithFullWhiteMask() {
        let result = computeSubjectFromBBox(box: CropRect(x: 10, y: 20, width: 30, height: 40), w: 100, h: 100)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.bbox.x, 10)
        XCTAssertEqual(result!.bbox.y, 20)
        XCTAssertEqual(result!.bbox.width, 30)
        XCTAssertEqual(result!.bbox.height, 40)
        XCTAssertEqual(result!.mask?.count, 10000)
        XCTAssertEqual(result!.mask?[0], 255)
    }

    func testComputeSubjectFromBBoxClampsToImageBounds() {
        let result = computeSubjectFromBBox(box: CropRect(x: -5, y: -5, width: 200, height: 200), w: 100, h: 100)
        XCTAssertEqual(result!.bbox.x, 0)
        XCTAssertEqual(result!.bbox.y, 0)
        XCTAssertEqual(result!.bbox.width, 100)
        XCTAssertEqual(result!.bbox.height, 100)
    }

    // MARK: - computeSquareCropParams

    func testComputeSquareCropParamsReturnsSquareCropCenteredOnBbox() {
        let params = computeSquareCropParams(bbox: CropRect(x: 40, y: 40, width: 20, height: 20), imgW: 200, imgH: 200)
        // side=20, padding=3, cropSize=ceil(26)=26
        XCTAssertEqual(params.cropSize, 26)
        let halfCrop = Int(Double(params.cropSize) / 2)
        // cx = floor(40 + 10) = 50
        let expectedX = 50 - halfCrop
        XCTAssertEqual(params.cropX, expectedX)
    }

    func testComputeSquareCropParamsClampsCropXTo0() {
        let params = computeSquareCropParams(bbox: CropRect(x: 0, y: 0, width: 20, height: 20), imgW: 200, imgH: 200)
        XCTAssertEqual(params.cropX, 0)
        XCTAssertEqual(params.cropY, 0)
    }

    func testComputeSquareCropParamsClampsToImageEdge() {
        let params = computeSquareCropParams(bbox: CropRect(x: 180, y: 180, width: 20, height: 20), imgW: 200, imgH: 200)
        XCTAssertLessThanOrEqual(params.cropX + params.cropSize, 200)
        XCTAssertLessThanOrEqual(params.cropY + params.cropSize, 200)
    }

    // MARK: - cropPixelsToSquare

    func testCropPixelsToSquareExtractsCorrectRegion() {
        // 4x4 image, crop 2x2 from (1,1)
        var full = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for i in 0..<full.count { full[i] = UInt8(i) }
        let cropped = cropPixelsToSquare(full, srcW: 4, cropX: 1, cropY: 1, cropSize: 2)
        XCTAssertEqual(cropped.count, 2 * 2 * 4)
        // First pixel from (1,1): index = ((1*4+1)*4) = 20
        XCTAssertEqual(cropped[0], 20)
    }

    func testCropPixelsToSquareHandles1x1Crop() {
        var full = [UInt8](repeating: 0, count: 2 * 2 * 4)
        for i in 0..<full.count { full[i] = 100 }
        let cropped = cropPixelsToSquare(full, srcW: 2, cropX: 0, cropY: 0, cropSize: 1)
        XCTAssertEqual(cropped.count, 4)
        XCTAssertEqual(cropped[0], 100)
    }

    // MARK: - cropMaskToSquare

    func testCropMaskToSquareExtractsCorrectValues() {
        // 3x3 mask, crop 2x2 from (1,0)
        let mask: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        let cropped = cropMaskToSquare(mask, srcW: 3, cropX: 1, cropY: 0, cropSize: 2)
        XCTAssertEqual(cropped.count, 4)
        // Row 0: mask[1]=2, mask[2]=3
        XCTAssertEqual(cropped[0], 2)
        XCTAssertEqual(cropped[1], 3)
        // Row 1: mask[4]=5, mask[5]=6
        XCTAssertEqual(cropped[2], 5)
        XCTAssertEqual(cropped[3], 6)
    }

    func testCropMaskToSquareReturns0ForOutOfBounds() {
        let mask: [UInt8] = [1]
        let cropped = cropMaskToSquare(mask, srcW: 1, cropX: 0, cropY: 0, cropSize: 2)
        XCTAssertEqual(cropped.count, 4)
        XCTAssertEqual(cropped[0], 1)
        XCTAssertEqual(cropped[1], 0)
        XCTAssertEqual(cropped[2], 0)
        XCTAssertEqual(cropped[3], 0)
    }

    // MARK: - adjustSubjectForCrop

    func testAdjustSubjectForCropShiftsBboxByCropOrigin() {
        let result = adjustSubjectForCrop(
            originalBbox: CropRect(x: 50, y: 60, width: 20, height: 30),
            cropX: 40, cropY: 40, cropSize: 100)
        XCTAssertEqual(result.bbox.x, 10)
        XCTAssertEqual(result.bbox.y, 20)
        XCTAssertEqual(result.bbox.width, 20)
        XCTAssertEqual(result.bbox.height, 30)
    }

    func testAdjustSubjectForCropClampsWidthToCropSize() {
        let result = adjustSubjectForCrop(
            originalBbox: CropRect(x: 50, y: 60, width: 200, height: 300),
            cropX: 40, cropY: 40, cropSize: 100)
        XCTAssertEqual(result.bbox.width, 100)
        XCTAssertEqual(result.bbox.height, 100)
    }

    // MARK: - adjustPoseForCrop

    func testAdjustPoseForCropMapsNormalizedSourcePointsIntoCropSpace() {
        let pose = adjustPoseForCrop(
            BeadPoseData(keypoints: [BeadPoseKeypoint(x: 0.5, y: 0.25, confidence: 0.8)]),
            sourceWidth: 200, sourceHeight: 100, cropX: 50, cropY: 0, cropSize: 100)
        XCTAssertNotNil(pose)
        // (0.5 * 200 - 50) / 100 = (100 - 50) / 100 = 0.5
        // (0.25 * 100 - 0) / 100 = 0.25
        XCTAssertEqual(pose!.keypoints[0].x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(pose!.keypoints[0].y, 0.25, accuracy: 1e-9)
        XCTAssertEqual(pose!.keypoints[0].confidence, 0.8, accuracy: 1e-9)
    }

    // MARK: - iOS 边界增强

    func testAdjustPoseForCropReturnsNilForInvalidInputs() {
        XCTAssertNil(adjustPoseForCrop(nil, sourceWidth: 100, sourceHeight: 100, cropX: 0, cropY: 0, cropSize: 50))
        XCTAssertNil(adjustPoseForCrop(BeadPoseData(keypoints: []), sourceWidth: 0, sourceHeight: 100, cropX: 0, cropY: 0, cropSize: 50))
        XCTAssertNil(adjustPoseForCrop(BeadPoseData(keypoints: []), sourceWidth: 100, sourceHeight: 100, cropX: 0, cropY: 0, cropSize: 0))
    }

    func testAdjustPoseForCropClampsToUnitRange() {
        // 关键点映射后会超出 [0,1]，应被 clamp
        let pose = adjustPoseForCrop(
            BeadPoseData(keypoints: [BeadPoseKeypoint(x: 0.0, y: 0.0, confidence: 1.0)]),
            sourceWidth: 200, sourceHeight: 200, cropX: 100, cropY: 100, cropSize: 50)
        // (0*200 - 100)/50 = -2 → clamp to 0
        XCTAssertEqual(pose!.keypoints[0].x, 0)
        XCTAssertEqual(pose!.keypoints[0].y, 0)
    }

    func testComputeSubjectFromBBoxMaskIsAllWhite() {
        let result = computeSubjectFromBBox(box: CropRect(x: 10, y: 10, width: 10, height: 10), w: 50, h: 50)
        XCTAssertEqual(result!.mask?.count, 2500)
        XCTAssertTrue(result!.mask!.allSatisfy { $0 == 255 })
    }
}
