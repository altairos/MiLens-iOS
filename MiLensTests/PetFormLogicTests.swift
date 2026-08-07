import XCTest
@testable import MiLens

/// PetFormLogic 测试（对应源端 PetFormViewModel.test.ets）。
/// 覆盖表单默认状态、备注解析/格式化/校验、彩蛋判定、日期回退、未保存判定、
/// 备忘条目构建校验、视觉特征注册常量与校验。
///
/// 架构差异：源端 birthday 为字符串 + DatePickerResult 回调，故有 formatDatePickerResult/
/// resolveInitialDate 字符串往返用例；iOS 用 Date?，去掉字符串往返用例，保留 resolveInitialDate
/// 的空值回退语义用例。
final class PetFormLogicTests: XCTestCase {

    private let cal = PetDateCalendar.gregorian

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d
        return cal.date(from: dc)!
    }

    // MARK: - defaultPetFormState

    func testEmptyFormStateReturnsEmptyState() {
        let s = PetFormState.empty
        XCTAssertEqual(s.name, "")
        XCTAssertEqual(s.species, .unknown)
        XCTAssertEqual(s.gender, .unknown)
        XCTAssertNil(s.birthday)
        XCTAssertNil(s.adoptionDay)
        XCTAssertTrue(s.noteItems.isEmpty)
    }

    // MARK: - parseNoteItems

    func testParseNoteItemsReturnsEmptyForEmptyString() {
        XCTAssertTrue(PetFormLogic.parseNoteItems("").isEmpty)
    }

    func testParseNoteItemsReturnsEmptyForWhitespace() {
        XCTAssertTrue(PetFormLogic.parseNoteItems("   ").isEmpty)
    }

    func testParseNoteItemsStripsBulletPrefixes() {
        let result = PetFormLogic.parseNoteItems("· 第一条\n• 第二条\n- 第三条\n* 第四条")
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0], "第一条")
        XCTAssertEqual(result[1], "第二条")
        XCTAssertEqual(result[2], "第三条")
        XCTAssertEqual(result[3], "第四条")
    }

    func testParseNoteItemsFiltersEmptyLines() {
        let result = PetFormLogic.parseNoteItems("· A\n\n· B")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], "A")
        XCTAssertEqual(result[1], "B")
    }

    // MARK: - formatNoteItems

    func testFormatNoteItemsAddsBulletPrefix() {
        XCTAssertEqual(PetFormLogic.formatNoteItems(["A", "B"]), "· A\n· B")
    }

    func testFormatNoteItemsReturnsEmptyForEmptyArray() {
        XCTAssertEqual(PetFormLogic.formatNoteItems([]), "")
    }

    // ─── parse/format 往返 ───

    func testParseFormatRoundTripPreservesItems() {
        let original = ["买猫粮", "打疫苗"]
        let formatted = PetFormLogic.formatNoteItems(original)
        let parsed = PetFormLogic.parseNoteItems(formatted)
        XCTAssertEqual(parsed, original)
    }

    // MARK: - validateNoteItemLength

    func testValidateNoteItemLengthReturnsNilForValidItems() {
        XCTAssertNil(PetFormLogic.validateNoteItemLength(["短文本", "另一个"]))
    }

    func testValidateNoteItemLengthReturnsErrorForLongItems() {
        let longItem = String(repeating: "a", count: 36)
        let err = PetFormLogic.validateNoteItemLength([longItem])
        XCTAssertNotNil(err)
        XCTAssertTrue(err!.contains("25"))
    }

    func testValidateNoteItemLengthReturnsErrorWhenExceedingCustomMaxLen() {
        let err = PetFormLogic.validateNoteItemLength(["abcdef"], maxLen: 5)
        XCTAssertNotNil(err)
    }

    // MARK: - isEasterDate / hasBirthdayChanged（Date 版）

    func testIsEasterDateReturnsTrueForJuly3() {
        XCTAssertTrue(PetFormLogic.isEasterDate(date(2024, 7, 3), calendar: cal))
    }

    func testIsEasterDateReturnsFalseForOtherDates() {
        XCTAssertFalse(PetFormLogic.isEasterDate(date(2024, 6, 15), calendar: cal))
    }

    func testIsEasterDateReturnsFalseForNil() {
        XCTAssertFalse(PetFormLogic.isEasterDate(nil, calendar: cal))
    }

    func testHasBirthdayChangedReturnsTrueWhenChangingToEasterDate() {
        XCTAssertTrue(PetFormLogic.hasBirthdayChanged(
            previous: date(2024, 6, 15), current: date(2024, 7, 3), calendar: cal))
    }

    func testHasBirthdayChangedReturnsFalseWhenNotChangingToEasterDate() {
        XCTAssertFalse(PetFormLogic.hasBirthdayChanged(
            previous: date(2024, 6, 15), current: date(2024, 8, 1), calendar: cal))
    }

    func testHasBirthdayChangedReturnsFalseWhenAlreadyEasterDate() {
        XCTAssertFalse(PetFormLogic.hasBirthdayChanged(
            previous: date(2024, 7, 3), current: date(2024, 7, 3), calendar: cal))
    }

    func testHasBirthdayChangedReturnsTrueWhenPreviousNil() {
        // nil 对应源端空串——isEasterDate 返回 false，故 !false && true = true
        XCTAssertTrue(PetFormLogic.hasBirthdayChanged(
            previous: nil, current: date(2024, 7, 3), calendar: cal))
    }

    // MARK: - resolveInitialDate（Date 版，对应源端空值回退语义）

    func testResolveInitialDateReturnsDateWhenNonNil() {
        let d = date(2024, 6, 15)
        XCTAssertEqual(PetFormLogic.resolveInitialDate(d), d)
    }

    func testResolveInitialDateReturnsFallbackWhenNil() {
        let fallback = date(2000, 1, 1)
        XCTAssertEqual(PetFormLogic.resolveInitialDate(nil, fallback: fallback), fallback)
    }

    // MARK: - speciesEmoji（委托 PetProfileLogic）

    func testSpeciesEmojiReturnsCatForCat() {
        XCTAssertEqual(PetFormLogic.speciesEmoji(.cat), "\u{1F431}")
    }

    func testSpeciesEmojiReturnsDogForDog() {
        XCTAssertEqual(PetFormLogic.speciesEmoji(.dog), "\u{1F436}")
    }

    func testSpeciesEmojiReturnsPawForUnknown() {
        XCTAssertEqual(PetFormLogic.speciesEmoji(.unknown), "\u{1F43E}")
    }

    // MARK: - hasUnsavedChanges

    private func snapshot(
        name: String = "", species: Species = .unknown, gender: Gender = .unknown,
        birthday: Date? = nil, adoptionDay: Date? = nil,
        notes: String = "", avatarPath: String = ""
    ) -> PetFormLogic.PetComparisonSnapshot {
        PetFormLogic.PetComparisonSnapshot(
            name: name, species: species, gender: gender,
            birthday: birthday, adoptionDay: adoptionDay,
            notes: notes, avatarPath: avatarPath
        )
    }

    func testHasUnsavedChangesReturnsFalseWhenIdentical() {
        let snap = snapshot(name: "A", species: .cat, gender: .female,
                            birthday: date(2024, 1, 1), adoptionDay: date(2024, 2, 1),
                            notes: "n", avatarPath: "/p")
        XCTAssertFalse(PetFormLogic.hasUnsavedChanges(current: snap, original: snap))
    }

    func testHasUnsavedChangesReturnsTrueWhenNameDiffers() {
        let a = snapshot(name: "A")
        let b = snapshot(name: "B")
        XCTAssertTrue(PetFormLogic.hasUnsavedChanges(current: a, original: b))
    }

    func testHasUnsavedChangesReturnsTrueWhenAvatarPathDiffers() {
        let a = snapshot(avatarPath: "/x")
        let b = snapshot(avatarPath: "/y")
        XCTAssertTrue(PetFormLogic.hasUnsavedChanges(current: a, original: b))
    }

    func testHasUnsavedChangesReturnsTrueWhenNotesDiffer() {
        let a = snapshot(notes: "x")
        let b = snapshot(notes: "y")
        XCTAssertTrue(PetFormLogic.hasUnsavedChanges(current: a, original: b))
    }

    func testHasUnsavedChangesReturnsTrueWhenSpeciesDiffers() {
        let a = snapshot(species: .cat)
        let b = snapshot(species: .dog)
        XCTAssertTrue(PetFormLogic.hasUnsavedChanges(current: a, original: b))
    }

    func testHasUnsavedChangesReturnsTrueWhenBirthdayDiffers() {
        let a = snapshot(birthday: date(2024, 1, 1))
        let b = snapshot(birthday: date(2024, 6, 15))
        XCTAssertTrue(PetFormLogic.hasUnsavedChanges(current: a, original: b))
    }

    // MARK: - validateAndBuildNoteItem

    func testValidateAndBuildNoteItemReturnsOkForValidInput() {
        let r = PetFormLogic.validateAndBuildNoteItem("买猫粮")
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.item, "买猫粮")
        XCTAssertEqual(r.error, "")
    }

    func testValidateAndBuildNoteItemTrimsInput() {
        let r = PetFormLogic.validateAndBuildNoteItem("  hello  ")
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.item, "hello")
    }

    func testValidateAndBuildNoteItemRejectsEmptyInputSilently() {
        let r = PetFormLogic.validateAndBuildNoteItem("   ")
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.error, "")
    }

    func testValidateAndBuildNoteItemRejectsLongInputWithError() {
        let long = String(repeating: "a", count: 36)
        let r = PetFormLogic.validateAndBuildNoteItem(long)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.error.contains("25"))
    }

    // MARK: - 注册常量与校验

    func testRegistrationPhotoConstants() {
        XCTAssertEqual(PetFormConstants.minRegistrationPhotos, 8)
        XCTAssertEqual(PetFormConstants.maxRegistrationPhotos, 15)
    }

    func testResolveMaxSelectNumberSubtractsCurrentCount() {
        XCTAssertEqual(PetFormLogic.resolveMaxSelectNumber(currentCount: 0), PetFormConstants.maxRegistrationPhotos)
        XCTAssertEqual(PetFormLogic.resolveMaxSelectNumber(currentCount: 5), 10)
        XCTAssertEqual(PetFormLogic.resolveMaxSelectNumber(currentCount: 15), 0)
        XCTAssertEqual(PetFormLogic.resolveMaxSelectNumber(currentCount: 20), 0)
    }

    func testBuildRegPhotoFileNameContainsPetIDAndIndex() {
        let petID = UUID()
        let name = PetFormLogic.buildRegPhotoFileName(petID: petID, index: 3, timestamp: date(2024, 1, 1))
        XCTAssertTrue(name.hasPrefix("pet_\(petID.uuidString)_"))
        XCTAssertTrue(name.hasSuffix("_3.jpg"))
    }

    func testFormatRegistrationProgressIncludesCount() {
        XCTAssertEqual(PetFormLogic.formatRegistrationProgress(count: 8), "正在提取特征 (8 张照片)...")
    }

    func testResolveRegistrationValidationRejectsBelowMinimum() {
        XCTAssertEqual(PetFormLogic.resolveRegistrationValidation(uris: []), "请至少选择 8 张照片")
        XCTAssertEqual(PetFormLogic.resolveRegistrationValidation(uris: ["a", "b", "c"]), "请至少选择 8 张照片")
    }

    func testResolveRegistrationValidationAcceptsAtMinimum() {
        let uris = (0..<PetFormConstants.minRegistrationPhotos).map { "u\($0)" }
        XCTAssertEqual(PetFormLogic.resolveRegistrationValidation(uris: uris), "")
    }
}
