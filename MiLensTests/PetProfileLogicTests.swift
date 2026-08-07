import XCTest
@testable import MiLens

/// PetProfileLogic 测试（对应源端 PetProfileViewModel.test.ets）。
/// 覆盖彩蛋常量、物种 Emoji、名称校验、数量上限、彩蛋判定（MM-DD 提取 + 比较）。
final class PetProfileLogicTests: XCTestCase {

    // MARK: - 日期辅助（固定 UTC Gregorian，跨环境可复现）

    private let cal = PetDateCalendar.gregorian

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d
        return cal.date(from: dc)!
    }

    // MARK: - 彩蛋常量

    func testEasterEggBirthdayConstantEquals0703() {
        XCTAssertEqual(PetProfileConstants.easterEggBirthdayMMdd, "07-03")
    }

    // MARK: - speciesEmoji

    func testSpeciesEmojiCatReturnsCatEmoji() {
        XCTAssertEqual(PetProfileLogic.speciesEmoji(.cat), "\u{1F431}")
    }

    func testSpeciesEmojiDogReturnsDogEmoji() {
        XCTAssertEqual(PetProfileLogic.speciesEmoji(.dog), "\u{1F436}")
    }

    func testSpeciesEmojiUnknownReturnsPawEmoji() {
        XCTAssertEqual(PetProfileLogic.speciesEmoji(.unknown), "\u{1F43E}")
    }

    // MARK: - validateNewPetName

    func testValidateNewPetNameEmptyReturnsError() {
        XCTAssertEqual(PetProfileLogic.validateNewPetName(""), "请输入宠物名字")
    }

    func testValidateNewPetNameWhitespaceOnlyReturnsError() {
        XCTAssertEqual(PetProfileLogic.validateNewPetName("   "), "请输入宠物名字")
    }

    func testValidateNewPetNameValidReturnsNil() {
        XCTAssertNil(PetProfileLogic.validateNewPetName("小橘"))
    }

    func testValidateNewPetNameNameWithSpacesReturnsNil() {
        XCTAssertNil(PetProfileLogic.validateNewPetName("  小橘  "))
    }

    // MARK: - checkPetCountLimit

    func testCheckPetCountLimitAtLimitReturnsError() {
        XCTAssertEqual(PetProfileLogic.checkPetCountLimit(currentCount: 20, maxPets: 20), "最多支持管理 20 只伙伴")
    }

    func testCheckPetCountLimitOverLimitReturnsError() {
        XCTAssertEqual(PetProfileLogic.checkPetCountLimit(currentCount: 25, maxPets: 20), "最多支持管理 20 只伙伴")
    }

    func testCheckPetCountLimitUnderLimitReturnsNil() {
        XCTAssertNil(PetProfileLogic.checkPetCountLimit(currentCount: 5, maxPets: 20))
    }

    func testCheckPetCountLimitZeroReturnsNil() {
        XCTAssertNil(PetProfileLogic.checkPetCountLimit(currentCount: 0, maxPets: 20))
    }

    func testCheckPetCountLimitUsesDefaultMaxPets() {
        XCTAssertEqual(PetProfileLogic.checkPetCountLimit(currentCount: 20), "最多支持管理 20 只伙伴")
        XCTAssertNil(PetProfileLogic.checkPetCountLimit(currentCount: 19))
    }

    // MARK: - monthDayString

    func testMonthDayStringExtractsMMddFromDate() {
        XCTAssertEqual(PetProfileLogic.monthDayString(from: date(2020, 7, 3), calendar: cal), "07-03")
    }

    func testMonthDayStringPadsSingleDigits() {
        XCTAssertEqual(PetProfileLogic.monthDayString(from: date(2024, 1, 5), calendar: cal), "01-05")
    }

    func testMonthDayStringNilReturnsEmpty() {
        XCTAssertEqual(PetProfileLogic.monthDayString(from: nil, calendar: cal), "")
    }

    // MARK: - shouldShowEasterEgg

    func testShouldShowEasterEggMatchingMonthDayReturnsTrue() {
        XCTAssertTrue(PetProfileLogic.shouldShowEasterEgg(monthDay: "07-03"))
    }

    func testShouldShowEasterEggNonMatchingMonthDayReturnsFalse() {
        XCTAssertFalse(PetProfileLogic.shouldShowEasterEgg(monthDay: "07-04"))
    }

    func testShouldShowEasterEggEmptyReturnsFalse() {
        XCTAssertFalse(PetProfileLogic.shouldShowEasterEgg(monthDay: ""))
    }

    func testShouldShowEasterEggDifferentMonthReturnsFalse() {
        XCTAssertFalse(PetProfileLogic.shouldShowEasterEgg(monthDay: "06-03"))
    }

    func testShouldShowEasterEggDifferentDayReturnsFalse() {
        XCTAssertFalse(PetProfileLogic.shouldShowEasterEgg(monthDay: "07-15"))
    }

    // MARK: - 端到端：从 Date 到彩蛋判定（对应源端 shouldShowEasterEgg(birthday)）

    func testEasterEggFromMatchingBirthdayDateReturnsTrue() {
        let md = PetProfileLogic.monthDayString(from: date(2020, 7, 3), calendar: cal)
        XCTAssertTrue(PetProfileLogic.shouldShowEasterEgg(monthDay: md))
    }

    func testEasterEggFromNonMatchingBirthdayDateReturnsFalse() {
        let md = PetProfileLogic.monthDayString(from: date(2020, 6, 15), calendar: cal)
        XCTAssertFalse(PetProfileLogic.shouldShowEasterEgg(monthDay: md))
    }

    func testEasterEggFromNilBirthdayReturnsFalse() {
        let md = PetProfileLogic.monthDayString(from: nil, calendar: cal)
        XCTAssertFalse(PetProfileLogic.shouldShowEasterEgg(monthDay: md))
    }
}
