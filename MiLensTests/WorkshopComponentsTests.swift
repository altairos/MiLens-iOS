//  WorkshopComponentsTests —— WorkshopValueRail 数值格式化纯函数单测。
//  对应 Figma `Control/Workshop Value Rail` 数值标格式（+08 / −04 / 0）。

import XCTest
@testable import MiLens

final class WorkshopComponentsTests: XCTestCase {

    // MARK: - formatAdjustValueLabel

    func testFormatPositiveValue() {
        XCTAssertEqual(formatAdjustValueLabel(8), "+08")
        XCTAssertEqual(formatAdjustValueLabel(12), "+12")
        XCTAssertEqual(formatAdjustValueLabel(100), "+100")
    }

    func testFormatNegativeValue() {
        XCTAssertEqual(formatAdjustValueLabel(-4), "−04")
        XCTAssertEqual(formatAdjustValueLabel(-12), "−12")
        XCTAssertEqual(formatAdjustValueLabel(-100), "−100")
    }

    func testFormatZero() {
        XCTAssertEqual(formatAdjustValueLabel(0), "0")
    }

    func testFormatRounding() {
        XCTAssertEqual(formatAdjustValueLabel(7.6), "+08")
        XCTAssertEqual(formatAdjustValueLabel(-3.4), "−03")
        XCTAssertEqual(formatAdjustValueLabel(0.4), "0")
        XCTAssertEqual(formatAdjustValueLabel(0.6), "+01")
    }
}
