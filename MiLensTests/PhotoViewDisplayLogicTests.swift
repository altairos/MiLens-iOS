import XCTest
@testable import MiLens

/// PhotoViewDisplayLogic 测试（audit-6 P1-4：从 PhotoViewView 下沉的信息 Sheet 文案决策）。
/// 覆盖拍摄日期格式化（注入固定日历保证可复现）/标题回退/元数据行拼接。
final class PhotoViewDisplayLogicTests: XCTestCase {

    /// 固定 UTC 公历，避免测试机时区/日历设置影响格式化结果。
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d; dc.hour = h; dc.minute = min
        return cal.date(from: dc)!
    }

    // MARK: - dateLabel

    func testDateLabelFormatsChineseDateTime() {
        let label = PhotoViewDisplayLogic.dateLabel(takenAt: date(2026, 3, 5, 9, 7), calendar: cal)
        XCTAssertEqual(label, "2026年3月5日 · 09:07")
    }

    func testDateLabelPadsHourAndMinute() {
        let label = PhotoViewDisplayLogic.dateLabel(takenAt: date(2024, 12, 31, 23, 59), calendar: cal)
        XCTAssertEqual(label, "2024年12月31日 · 23:59")
    }

    func testDateLabelNilTakenAtReturnsEmpty() {
        XCTAssertEqual(PhotoViewDisplayLogic.dateLabel(takenAt: nil, calendar: cal), "")
    }

    // MARK: - titleText

    func testTitleTextReturnsNoteWhenPresent() {
        XCTAssertEqual(PhotoViewDisplayLogic.titleText(note: "窗台晒太阳"), "窗台晒太阳")
    }

    func testTitleTextEmptyNoteFallsBackToArchivedPlaceholder() {
        XCTAssertEqual(
            PhotoViewDisplayLogic.titleText(note: ""),
            String(localized: "photo.detail.archived")
        )
    }

    // MARK: - metadataText

    func testMetadataTextJoinsPetNameAndArchived() {
        let text = PhotoViewDisplayLogic.metadataText(petName: "咪咪")
        XCTAssertEqual(text, "咪咪 · \(String(localized: "photo.detail.archived"))")
    }

    func testMetadataTextEmptyPetNameReturnsArchivedOnly() {
        XCTAssertEqual(
            PhotoViewDisplayLogic.metadataText(petName: ""),
            String(localized: "photo.detail.archived")
        )
    }
}
