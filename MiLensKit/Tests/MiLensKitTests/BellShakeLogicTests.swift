import XCTest
@testable import MiLensKit

//  BellShakeLogic 纯决策逻辑测试。
//  覆盖：ShakeMode × hasAnniversary × hasNewPhoto 全矩阵（16 组合）、shouldAnimate。

final class BellShakeLogicTests: XCTestCase {

    // MARK: - resolveReason 全矩阵（4 mode × 2 hasAnniversary × 2 hasNewPhoto）

    // --- mode = .off（全部过滤）---

    func testOffModeNoTriggers() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: false, hasNewPhoto: false, mode: .off),
            .none)
    }

    func testOffModeAnniversaryFiltered() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: true, hasNewPhoto: false, mode: .off),
            .none)
    }

    func testOffModeNewPhotoFiltered() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: false, hasNewPhoto: true, mode: .off),
            .none)
    }

    func testOffModeBothFiltered() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: true, hasNewPhoto: true, mode: .off),
            .none)
    }

    // --- mode = .newPhotoOnly ---

    func testNewPhotoOnlyNoTriggers() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: false, hasNewPhoto: false, mode: .newPhotoOnly),
            .none)
    }

    func testNewPhotoOnlyAnniversaryFiltered() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: true, hasNewPhoto: false, mode: .newPhotoOnly),
            .none)
    }

    func testNewPhotoOnlyNewPhotoAllowed() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: false, hasNewPhoto: true, mode: .newPhotoOnly),
            .newPhoto)
    }

    func testNewPhotoOnlyOnlyNewPhotoAllowedWhenBoth() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: true, hasNewPhoto: true, mode: .newPhotoOnly),
            .newPhoto)
    }

    // --- mode = .anniversaryOnly ---

    func testAnniversaryOnlyNoTriggers() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: false, hasNewPhoto: false, mode: .anniversaryOnly),
            .none)
    }

    func testAnniversaryOnlyAnniversaryAllowed() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: true, hasNewPhoto: false, mode: .anniversaryOnly),
            .anniversary)
    }

    func testAnniversaryOnlyNewPhotoFiltered() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: false, hasNewPhoto: true, mode: .anniversaryOnly),
            .none)
    }

    func testAnniversaryOnlyOnlyAnniversaryAllowedWhenBoth() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: true, hasNewPhoto: true, mode: .anniversaryOnly),
            .anniversary)
    }

    // --- mode = .all ---

    func testAllModeNoTriggers() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: false, hasNewPhoto: false, mode: .all),
            .none)
    }

    func testAllModeAnniversaryOnly() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: true, hasNewPhoto: false, mode: .all),
            .anniversary)
    }

    func testAllModeNewPhotoOnly() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: false, hasNewPhoto: true, mode: .all),
            .newPhoto)
    }

    func testAllModeBoth() {
        XCTAssertEqual(
            BellShakeLogic.resolveReason(hasAnniversary: true, hasNewPhoto: true, mode: .all),
            .both)
    }

    // MARK: - shouldAnimate

    func testShouldAnimateFalseForNone() {
        XCTAssertFalse(BellShakeLogic.shouldAnimate(.none))
    }

    func testShouldAnimateTrueForAnniversary() {
        XCTAssertTrue(BellShakeLogic.shouldAnimate(.anniversary))
    }

    func testShouldAnimateTrueForNewPhoto() {
        XCTAssertTrue(BellShakeLogic.shouldAnimate(.newPhoto))
    }

    func testShouldAnimateTrueForBoth() {
        XCTAssertTrue(BellShakeLogic.shouldAnimate(.both))
    }

    // MARK: - ShakeMode CaseIterable

    func testShakeModeHasFourCases() {
        XCTAssertEqual(BellShakeLogic.ShakeMode.allCases.count, 4)
    }

    func testShakeModeDefaultRawValue() {
        XCTAssertEqual(BellShakeLogic.ShakeMode.all.rawValue, "all")
    }
}
