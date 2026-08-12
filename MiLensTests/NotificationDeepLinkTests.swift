import XCTest
import MiLensKit
@testable import MiLens

/// NotificationDeepLink 纯解析逻辑测试——里程碑通知标识符 → tap 路由目的地。
/// 验证标识符编解码的正确性（UUID 含连字符的边界），以及非里程碑通知的排除语义。
final class NotificationDeepLinkTests: XCTestCase {

    private let petID = UUID(uuidString: "AABBCCDD-EEFF-1144-7788-001122334455")!

    // MARK: - 里程碑通知路由

    func testMilestoneIdentifierResolvesToPetCardMilestone() {
        let identifier = NotifyService.milestoneIdentifier(for: Pet(name: "小橘", id: petID), days: 100)

        let destination = NotificationDeepLink.destination(fromIdentifier: identifier)

        XCTAssertEqual(destination?.petID, petID)
        XCTAssertEqual(destination?.kind, .milestone)
    }

    func testMilestoneIdentifierFor1000DaysResolves() {
        let identifier = NotifyService.milestoneIdentifier(for: Pet(name: "小橘", id: petID), days: 1000)

        let destination = NotificationDeepLink.destination(fromIdentifier: identifier)

        XCTAssertEqual(destination?.petID, petID)
        XCTAssertEqual(destination?.kind, .milestone)
    }

    // MARK: - UUID 连字符边界

    func testHandlesUUIDWithInternalHyphens() {
        // 直接构造含 UUID（4 个内部连字符）的标识符，验证最后一个 "-" 分隔天数
        let identifier = "milestone-\(petID.uuidString)-365"

        let destination = NotificationDeepLink.destination(fromIdentifier: identifier)

        XCTAssertEqual(destination?.petID, petID)
    }

    func testLowercaseUUIDAccepted() {
        let lower = UUID(uuidString: "aabbccdd-eeff-1144-7788-001122334455")!
        let identifier = NotifyService.milestoneIdentifier(for: Pet(name: "小橘", id: lower), days: 730)

        let destination = NotificationDeepLink.destination(fromIdentifier: identifier)

        XCTAssertEqual(destination?.petID, lower)
    }

    // MARK: - 非里程碑通知排除

    func testAnniversaryIdentifierReturnsNil() {
        let pet = Pet(name: "小橘", id: petID)
        let identifier = NotifyService.anniversaryIdentifier(for: pet, kind: .birthday)

        XCTAssertNil(NotificationDeepLink.destination(fromIdentifier: identifier))
    }

    func testTimeMachineIdentifierReturnsNil() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let identifier = NotifyService.timeMachineIdentifier(
            for: cal.date(from: DateComponents(year: 2026, month: 8, day: 13))!, calendar: cal)

        XCTAssertNil(NotificationDeepLink.destination(fromIdentifier: identifier))
    }

    // MARK: - 无效格式

    func testEmptyStringReturnsNil() {
        XCTAssertNil(NotificationDeepLink.destination(fromIdentifier: ""))
    }

    func testInvalidUUIDReturnsNil() {
        XCTAssertNil(NotificationDeepLink.destination(fromIdentifier: "milestone-NOT-A-UUID-100"))
    }

    func testMilestonePrefixOnlyReturnsNil() {
        XCTAssertNil(NotificationDeepLink.destination(fromIdentifier: "milestone-"))
    }
}
