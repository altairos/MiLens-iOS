import XCTest
@testable import MiLensKit

final class RedPacketMaskQualityLogicTests: XCTestCase {
    func testCleanCentralSubjectHasSingleComponentAndNoBoundaryContact() throws {
        let mask = makeMask(width: 40, height: 40) { x, y in
            x >= 10 && x < 30 && y >= 8 && y < 32
        }
        let metrics = try XCTUnwrap(
            RedPacketMaskQualityLogic.analyze(mask: mask, width: 40, height: 40)
        )

        XCTAssertEqual(metrics.fragmentationRatio, 0, accuracy: 0.001)
        XCTAssertEqual(metrics.boundaryTouchRatio, 0, accuracy: 0.001)
        XCTAssertLessThan(metrics.edgeRoughness, 0.3)
        XCTAssertEqual(metrics.foregroundRatio, 0.3, accuracy: 0.001)
    }

    func testFragmentedMaskReportsDisconnectedForeground() throws {
        let mask = makeMask(width: 40, height: 40) { x, y in
            (x >= 4 && x < 12 && y >= 4 && y < 12) ||
            (x >= 28 && x < 36 && y >= 28 && y < 36)
        }
        let metrics = try XCTUnwrap(
            RedPacketMaskQualityLogic.analyze(mask: mask, width: 40, height: 40)
        )

        XCTAssertEqual(metrics.fragmentationRatio, 0.5, accuracy: 0.001)
    }

    func testBoundaryContactIsMeasured() throws {
        let mask = makeMask(width: 30, height: 30) { x, y in
            x < 12 && y >= 3 && y < 27
        }
        let metrics = try XCTUnwrap(
            RedPacketMaskQualityLogic.analyze(mask: mask, width: 30, height: 30)
        )

        XCTAssertGreaterThan(metrics.boundaryTouchRatio, 0.1)
    }

    func testEmptyMaskReturnsZeroMetrics() throws {
        let metrics = try XCTUnwrap(
            RedPacketMaskQualityLogic.analyze(
                mask: Data(repeating: 0, count: 100), width: 10, height: 10
            )
        )
        XCTAssertEqual(metrics, RedPacketMaskMetrics())
    }

    func testMalformedMaskReturnsNil() {
        XCTAssertNil(RedPacketMaskQualityLogic.analyze(
            mask: Data(repeating: 255, count: 10), width: 10, height: 10
        ))
    }

    private func makeMask(
        width: Int, height: Int, foreground: (Int, Int) -> Bool
    ) -> Data {
        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width where foreground(x, y) {
                values[y * width + x] = 255
            }
        }
        return Data(values)
    }
}
