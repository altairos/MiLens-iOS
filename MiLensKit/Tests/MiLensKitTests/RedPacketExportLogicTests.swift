import XCTest
@testable import MiLensKit

// RedPacketExportLogicTests — 导出决策纯逻辑测试（对应红包封面开发计划 §6.3）。
final class RedPacketExportLogicTests: XCTestCase {

    let maxBytes = WeChatRedPacketSpec.coverImageMaxBytes

    // MARK: - chooseBest

    func testSmallPNGChosenFirst() {
        let png = Data(repeating: 0x89, count: 100_000) // ~100KB
        let result = RedPacketExportLogic.chooseBest(png: png, jpegHigh: nil, jpegLow: nil)
        XCTAssertEqual(result?.format, .png)
        XCTAssertEqual(result?.fileExtension, "png")
    }

    func testLargePNGFallsBackToJPEGHigh() {
        let png = Data(repeating: 0x89, count: maxBytes + 100) // 超 500KB
        let jpegHigh = Data(repeating: 0xFF, count: 300_000) // ~300KB ≤ 限
        let result = RedPacketExportLogic.chooseBest(png: png, jpegHigh: jpegHigh, jpegLow: nil)
        XCTAssertEqual(result?.format, .jpeg)
        XCTAssertEqual(result?.fileExtension, "jpg")
    }

    func testLargePNGAndJPEGHighFallbackToJPEGLow() {
        let png = Data(repeating: 0x89, count: maxBytes + 100)
        let jpegHigh = Data(repeating: 0xFF, count: maxBytes + 50) // 超 500KB
        let jpegLow = Data(repeating: 0xFF, count: 200_000) // ~200KB ≤ 限
        let result = RedPacketExportLogic.chooseBest(png: png, jpegHigh: jpegHigh, jpegLow: jpegLow)
        XCTAssertEqual(result?.format, .jpeg)
        XCTAssertEqual(result?.fileExtension, "jpg")
        XCTAssertEqual(result?.data.count, 200_000)
    }

    func testAllOverLimitReturnsSmallest() {
        let png = Data(repeating: 0x89, count: maxBytes + 500)
        let jpegHigh = Data(repeating: 0xFF, count: maxBytes + 200)
        let jpegLow = Data(repeating: 0xFF, count: maxBytes + 100) // 最小
        let result = RedPacketExportLogic.chooseBest(png: png, jpegHigh: jpegHigh, jpegLow: jpegLow)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.format, .jpeg)
        XCTAssertEqual(result?.data.count, maxBytes + 100)
    }

    func testAllNilReturnsNil() {
        let result = RedPacketExportLogic.chooseBest(png: nil, jpegHigh: nil, jpegLow: nil)
        XCTAssertNil(result)
    }

    func testNilPNGButValidJPEG() {
        let jpegHigh = Data(repeating: 0xFF, count: 200_000)
        let result = RedPacketExportLogic.chooseBest(png: nil, jpegHigh: jpegHigh, jpegLow: nil)
        XCTAssertEqual(result?.format, .jpeg)
    }

    func testExactlyAtLimit() {
        let png = Data(repeating: 0x89, count: maxBytes) // 恰好等于限制
        let result = RedPacketExportLogic.chooseBest(png: png, jpegHigh: nil, jpegLow: nil)
        XCTAssertEqual(result?.format, .png, "恰好等于限制应通过")
    }

    func testOneByteOverLimit() {
        let png = Data(repeating: 0x89, count: maxBytes + 1) // 超 1 字节
        let result = RedPacketExportLogic.chooseBest(png: png, jpegHigh: nil, jpegLow: nil)
        XCTAssertNotNil(result, "PNG 超限无 JPEG 时仍返回 PNG")
        XCTAssertEqual(result?.format, .png)
    }

    // MARK: - isWithinSizeLimit

    func testIsWithinSizeLimitTrue() {
        let data = Data(repeating: 0, count: maxBytes)
        XCTAssertTrue(RedPacketExportLogic.isWithinSizeLimit(data))
    }

    func testIsWithinSizeLimitFalse() {
        let data = Data(repeating: 0, count: maxBytes + 1)
        XCTAssertFalse(RedPacketExportLogic.isWithinSizeLimit(data))
    }

    // MARK: - chatThumbnailSpec

    func testChatThumbnailSpecHasValidSize() {
        let spec = RedPacketExportLogic.chatThumbnailSpec()
        XCTAssertGreaterThan(spec.width, 0)
        XCTAssertGreaterThan(spec.height, 0)
        XCTAssertGreaterThan(spec.height, spec.width, "缩略图应为竖向比例")
    }

    func testChatThumbnailSpecMatchesCoverRatio() {
        let spec = RedPacketExportLogic.chatThumbnailSpec()
        let coverRatio = Double(WeChatRedPacketSpec.coverImageHeight) /
                         Double(WeChatRedPacketSpec.coverImageWidth)
        let thumbRatio = Double(spec.height) / Double(spec.width)
        XCTAssertEqual(thumbRatio, coverRatio, accuracy: 0.1, "缩略图比例应与封面一致")
    }

    // MARK: - exportFilename

    func testExportFilenameWithPetName() {
        let name = RedPacketExportLogic.exportFilename(petName: "咪咪", fileExtension: "png")
        XCTAssertTrue(name.contains("咪咪"))
        XCTAssertTrue(name.hasSuffix(".png"))
    }

    func testExportFilenameWithJPGExtension() {
        let name = RedPacketExportLogic.exportFilename(petName: "咪咪", fileExtension: "jpg")
        XCTAssertTrue(name.hasSuffix(".jpg"))
    }

    func testExportFilenameEmptyPetName() {
        let name = RedPacketExportLogic.exportFilename(petName: "")
        XCTAssertFalse(name.isEmpty)
    }
}
