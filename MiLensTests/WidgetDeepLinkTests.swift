import XCTest
@testable import MiLens

//  WidgetDeepLink 深链解析测试。
//
//  覆盖 WidgetKit-Design.md §6.3 的深链映射契约：
//  - photo/{uuid} → .photoView
//  - pet/{uuid} → .petProfile
//  - timeline → .timeline
//  - bead/{uuid} → .beadPattern
//  - anniversary/{petUUID}?day={dayID} → .petProfile（dayID 预留）
//  - 无效 scheme / host / UUID → nil（安全回退）

final class WidgetDeepLinkTests: XCTestCase {

    private let testUUID = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

    func testPhotoDeepLink() {
        let url = URL(string: "milens://photo/550e8400-e29b-41d4-a716-446655440000")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertEqual(route, .photoView(photoID: testUUID))
    }

    func testPetDeepLink() {
        let url = URL(string: "milens://pet/550e8400-e29b-41d4-a716-446655440000")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertEqual(route, .petProfile(petID: testUUID))
    }

    func testTimelineDeepLink() {
        let url = URL(string: "milens://timeline")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertEqual(route, .timeline)
    }

    func testBeadDeepLink() {
        let url = URL(string: "milens://bead/550e8400-e29b-41d4-a716-446655440000")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertEqual(route, .beadPattern(photoID: testUUID))
    }

    // MARK: - 纪念日深链

    func testAnniversaryDeepLink() {
        // anniversary 带合法 petUUID + day query → petProfile
        let url = URL(string: "milens://anniversary/550e8400-e29b-41d4-a716-446655440000?day=birthday:abc")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertEqual(route, .petProfile(petID: testUUID),
                       "anniversary 深链应解析为 petProfile（day query 预留不消费）")
    }

    func testAnniversaryDeepLink_invalidUUID_returnsNil() {
        // petUUID 无效时安全回退 nil（query 存在不影响判定）
        let url = URL(string: "milens://anniversary/not-a-uuid?day=birthday:abc")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertNil(route, "anniversary 路径 petUUID 无效应返回 nil")
    }

    func testHomeDeepLink_returnsNil() {
        let url = URL(string: "milens://home")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertNil(route, "home 深链应返回 nil（调用方切 Tab，无需 push Route）")
    }

    // MARK: - 无效输入

    func testWrongScheme_returnsNil() {
        let url = URL(string: "https://photo/550e8400-e29b-41d4-a716-446655440000")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertNil(route, "非 milens:// scheme 应返回 nil")
    }

    func testInvalidHost_returnsNil() {
        let url = URL(string: "milens://unknown")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertNil(route, "未知 host 应返回 nil")
    }

    func testInvalidUUID_returnsNil() {
        let url = URL(string: "milens://photo/not-a-uuid")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertNil(route, "无效 UUID 应返回 nil（安全回退）")
    }

    func testMissingPath_returnsNil() {
        let url = URL(string: "milens://photo")!
        let route = WidgetDeepLink.route(from: url)
        XCTAssertNil(route, "photo 缺少 UUID 应返回 nil")
    }
}
