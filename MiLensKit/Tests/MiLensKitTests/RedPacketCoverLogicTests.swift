import XCTest
@testable import MiLensKit

//  WeChatRedPacketSpec + RedPacketCoverLogic 纯决策逻辑测试（创作 Tab 红包封面项目）。
//
//  无源端黄金规格（红包封面为 iOS 自研创作项目），行为规格由本文件守护：
//  - 规格常量：对齐微信官方《制作规范》硬约束
//  - 封面简称：截断到 8 字、空名回退
//  - 校验：尺寸/格式/大小三类结果
//  - 上传引导：步骤 key 数量、文件名

// MARK: - 规格常量

final class WeChatRedPacketSpecTests: XCTestCase {

    func testCoverImageSize() {
        XCTAssertEqual(WeChatRedPacketSpec.coverImageWidth, 957)
        XCTAssertEqual(WeChatRedPacketSpec.coverImageHeight, 1278)
    }

    func testCoverImageMaxBytes() {
        XCTAssertEqual(WeChatRedPacketSpec.coverImageMaxBytes, 500 * 1024)
    }

    func testStoryImageSize() {
        XCTAssertEqual(WeChatRedPacketSpec.storyImageWidth, 750)
        XCTAssertEqual(WeChatRedPacketSpec.storyImageHeight, 1250)
    }

    func testStoryImageMaxBytes() {
        XCTAssertEqual(WeChatRedPacketSpec.storyImageMaxBytes, 300 * 1024)
    }

    func testLogoConstraints() {
        XCTAssertEqual(WeChatRedPacketSpec.logoMaxWidth, 200)
        XCTAssertEqual(WeChatRedPacketSpec.logoMaxHeight, 200)
        XCTAssertEqual(WeChatRedPacketSpec.logoMaxBytes, 100 * 1024)
    }

    func testCoverTitleMaxLength() {
        XCTAssertEqual(WeChatRedPacketSpec.coverTitleMaxLength, 8)
    }

    func testValidImageFormats() {
        XCTAssertEqual(Set(WeChatRedPacketSpec.validImageFormats), ["png", "jpg", "jpeg"])
    }

    func testSafeZoneRatioWithinValidRange() {
        XCTAssertGreaterThan(WeChatRedPacketSpec.safeZoneTopRatio, 0.3)
        XCTAssertLessThan(WeChatRedPacketSpec.safeZoneTopRatio, 0.8)
    }
}

// MARK: - 封面简称

final class RedPacketCoverTitleTests: XCTestCase {

    func testShortNameUnchanged() {
        XCTAssertEqual(RedPacketCoverLogic.coverTitle(petName: "咪咪"), "咪咪")
    }

    func testTruncatesToMaxLength() {
        let longName = String(repeating: "字", count: 12)
        XCTAssertEqual(RedPacketCoverLogic.coverTitle(petName: longName).count, 8)
    }

    func testEmptyNameFallback() {
        XCTAssertEqual(RedPacketCoverLogic.coverTitle(petName: ""), "我的红包封面")
    }

    func testExactlyAtMaxLength() {
        let name = String(repeating: "字", count: 8)
        XCTAssertEqual(RedPacketCoverLogic.coverTitle(petName: name).count, 8)
    }
}

// MARK: - 规格校验

final class RedPacketCoverValidationTests: XCTestCase {

    private let validW = WeChatRedPacketSpec.coverImageWidth
    private let validH = WeChatRedPacketSpec.coverImageHeight

    func testValidCoverImage() {
        let smallData = Data(repeating: 0xFF, count: 100_000) // 100KB < 500KB
        let result = RedPacketCoverLogic.validateCoverImage(
            data: smallData, width: validW, height: validH, fileExtension: "png")
        XCTAssertEqual(result, .valid)
    }

    func testInvalidFormat() {
        let result = RedPacketCoverLogic.validateCoverImage(
            data: Data(), width: validW, height: validH, fileExtension: "gif")
        XCTAssertEqual(result, .invalidFormat)
    }

    func testFormatCaseInsensitive() {
        let smallData = Data(repeating: 0xFF, count: 100_000)
        let result = RedPacketCoverLogic.validateCoverImage(
            data: smallData, width: validW, height: validH, fileExtension: "PNG")
        XCTAssertEqual(result, .valid)
    }

    func testInvalidSize() {
        let result = RedPacketCoverLogic.validateCoverImage(
            data: Data(), width: 800, height: 600, fileExtension: "png")
        if case .invalidSize(let expected, let actual) = result {
            XCTAssertEqual(expected.width, validW)
            XCTAssertEqual(expected.height, validH)
            XCTAssertEqual(actual.width, 800)
            XCTAssertEqual(actual.height, 600)
        } else {
            XCTFail("期望 invalidSize，得到 \(result)")
        }
    }

    func testInvalidFileSize() {
        let largeData = Data(repeating: 0xFF, count: 600 * 1024) // 600KB > 500KB
        let result = RedPacketCoverLogic.validateCoverImage(
            data: largeData, width: validW, height: validH, fileExtension: "png")
        if case .invalidFileSize(let maxBytes, let actualBytes) = result {
            XCTAssertEqual(maxBytes, 500 * 1024)
            XCTAssertEqual(actualBytes, 600 * 1024)
        } else {
            XCTFail("期望 invalidFileSize，得到 \(result)")
        }
    }

    // MARK: - 封面故事图校验

    func testValidStoryImage() {
        let data = Data(repeating: 0xFF, count: 100_000)
        let result = RedPacketCoverLogic.validateStoryImage(
            data: data, width: WeChatRedPacketSpec.storyImageWidth,
            height: WeChatRedPacketSpec.storyImageHeight)
        XCTAssertEqual(result, .valid)
    }

    func testInvalidStoryImageSize() {
        let result = RedPacketCoverLogic.validateStoryImage(
            data: Data(), width: 700, height: 1000)
        if case .invalidSize = result {
            // ok
        } else {
            XCTFail("期望 invalidSize，得到 \(result)")
        }
    }
}

// MARK: - 上传引导

final class RedPacketUploadGuideTests: XCTestCase {

    func testUploadGuideHasFiveSteps() {
        XCTAssertEqual(RedPacketCoverLogic.uploadGuideSteps().count, 5)
    }

    func testAllStepsAreLocalizationKeys() {
        for key in RedPacketCoverLogic.uploadGuideSteps() {
            XCTAssertTrue(key.hasPrefix("redpacket.guide."), "步骤 key 应以 redpacket.guide. 开头")
        }
    }

    func testEligibilityNoticeKey() {
        XCTAssertEqual(RedPacketCoverLogic.eligibilityNoticeKey(), "redpacket.guide.eligibility")
    }
}

// MARK: - 文件名

final class RedPacketFilenameTests: XCTestCase {

    func testFilenameWithPetName() {
        XCTAssertEqual(RedPacketCoverLogic.exportFilename(petName: "咪咪"), "redpacket_cover_咪咪.png")
    }

    func testFilenameWithEmptyName() {
        XCTAssertEqual(RedPacketCoverLogic.exportFilename(petName: ""), "redpacket_cover_pet.png")
    }
}
