import XCTest
@testable import MiLensKit

/// P0 占位测试，验证 MiLensKit 依赖链与测试 target 可运行。
/// P1 起按源端 `shared` 225 用例 + ArkTS/C++ parity 逐条翻译拼豆算法测试。
final class MiLensKitTests: XCTestCase {
    func testVersionIsExposed() {
        XCTAssertEqual(MiLensKit.version, "0.1.0")
    }
}
