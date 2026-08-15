import XCTest
@testable import MiLens
import MiLensKit

/// RedPacketCoverEncodeLogic 测试（audit-6 P1-4：从 RedPacketUploadGuideView 下沉的编码链决策）。
/// 编码器用假闭包注入（固定字节数/记录请求质量），验证字节预算决策链本身；
/// 真实 PNG/JPEG 编码属 UIKit 能力，不在本测试范围。
final class RedPacketCoverEncodeLogicTests: XCTestCase {

    /// 小预算（16 字节）便于用个位数 Data 触发各级回退。
    private let maxBytes = 16

    private func data(_ byte: UInt8, _ count: Int) -> Data {
        Data(repeating: byte, count: count)
    }

    // MARK: - 保存链

    func testSavePrefersPNGWhenWithinBudget() {
        let png = data(1, 10)
        let result = RedPacketCoverEncodeLogic.encodeForSave(
            pngData: { png },
            jpegData: { _ in data(2, 10) },
            maxBytes: maxBytes
        )
        XCTAssertEqual(result, png)
    }

    func testSaveFallsBackToHighQualityJPEGWhenPNGTooLarge() {
        var requestedQualities: [Double] = []
        let jpg = data(2, 12)
        let result = RedPacketCoverEncodeLogic.encodeForSave(
            pngData: { data(1, 100) },
            jpegData: { q in requestedQualities.append(q); return jpg },
            maxBytes: maxBytes
        )
        XCTAssertEqual(result, jpg)
        XCTAssertEqual(requestedQualities, [0.9])
    }

    func testSaveFallsBackToLowQualityJPEGWhenBothTooLarge() {
        var requestedQualities: [Double] = []
        let jpg06 = data(3, 20)
        let result = RedPacketCoverEncodeLogic.encodeForSave(
            pngData: { data(1, 100) },
            jpegData: { q in
                requestedQualities.append(q)
                return q == 0.9 ? data(2, 100) : jpg06
            },
            maxBytes: maxBytes
        )
        XCTAssertEqual(result, jpg06)
        XCTAssertEqual(requestedQualities, [0.9, 0.6])
    }

    /// 源端语义：JPEG(0.6) 兜底结果不检查预算（已尽力压缩，超限也写入）。
    func testSaveLowQualityFallbackIgnoresBudget() {
        let jpg06 = data(3, 100)
        let result = RedPacketCoverEncodeLogic.encodeForSave(
            pngData: { data(1, 100) },
            jpegData: { q in q == 0.9 ? data(2, 100) : jpg06 },
            maxBytes: maxBytes
        )
        XCTAssertEqual(result, jpg06)
    }

    func testSaveReturnsNilWhenAllEncodersFail() {
        let result = RedPacketCoverEncodeLogic.encodeForSave(
            pngData: { nil },
            jpegData: { _ in nil },
            maxBytes: maxBytes
        )
        XCTAssertNil(result)
    }

    // MARK: - 分享链

    func testSharePrefersPNGWhenWithinBudget() {
        let png = data(1, 10)
        let result = RedPacketCoverEncodeLogic.encodeForShare(
            pngData: { png },
            jpegData: { _ in data(2, 10) },
            maxBytes: maxBytes
        )
        XCTAssertEqual(result, png)
    }

    func testShareFallsBackToJpeg085WhenPNGTooLarge() {
        var requestedQualities: [Double] = []
        let jpg = data(2, 30)
        let result = RedPacketCoverEncodeLogic.encodeForShare(
            pngData: { data(1, 100) },
            jpegData: { q in requestedQualities.append(q); return jpg },
            maxBytes: maxBytes
        )
        XCTAssertEqual(result, jpg)
        XCTAssertEqual(requestedQualities, [0.85])
    }

    /// 源端语义：分享链 JPEG 失败回退空 Data，写入不因编码失败中断。
    func testShareFallsBackToEmptyDataWhenJpegFails() {
        let result = RedPacketCoverEncodeLogic.encodeForShare(
            pngData: { data(1, 100) },
            jpegData: { _ in nil },
            maxBytes: maxBytes
        )
        XCTAssertEqual(result, Data())
    }

    /// 守护默认预算与微信规格常量一致（500 KB），防止规格漂移。
    func testDefaultMaxBytesMatchesWeChatSpec() {
        XCTAssertEqual(WeChatRedPacketSpec.coverImageMaxBytes, 500 * 1024)
    }
}
