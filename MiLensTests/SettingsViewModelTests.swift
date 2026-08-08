import XCTest
@testable import MiLens

/// SettingsViewModel 测试：纪念提醒开关编排（授权→调度 / 拒绝→回弹 / 关闭→撤销）、
/// 版本号读取回退。复用 NotifyServiceTests 的内存仓储 + MockNotificationPoster。
@MainActor
final class SettingsViewModelTests: XCTestCase {

    private func makeViewModel(
        authorized: Bool
    ) -> (SettingsViewModel, MockNotificationPoster) {
        let poster = MockNotificationPoster()
        poster.authorizationResult = authorized
        let service = NotifyService(
            photoRepo: InMemoryPhotoRepository(photos: []),
            petRepo: InMemoryPetRepository(pets: []),
            poster: poster
        )
        return (SettingsViewModel(notifyService: service), poster)
    }

    // MARK: - 纪念提醒开关

    func testToggleOffCancelsAllAndKeepsOff() async {
        let (vm, poster) = makeViewModel(authorized: true)
        let kept = await vm.handleReminderToggle(enabled: false)
        XCTAssertFalse(kept)
        XCTAssertEqual(poster.removeAllCount, 1)
        XCTAssertFalse(vm.showReminderDeniedAlert)
    }

    func testToggleOnAuthorizedSchedulesAndStaysOn() async {
        let (vm, poster) = makeViewModel(authorized: true)
        let kept = await vm.handleReminderToggle(enabled: true)
        XCTAssertTrue(kept)
        // 幂等重调度先清空再按数据调度（空数据只清空）
        XCTAssertEqual(poster.removeAllCount, 1)
        XCTAssertFalse(vm.showReminderDeniedAlert)
    }

    func testToggleOnDeniedRollsBackAndPrompts() async {
        let (vm, poster) = makeViewModel(authorized: false)
        let kept = await vm.handleReminderToggle(enabled: true)
        XCTAssertFalse(kept)
        XCTAssertTrue(vm.showReminderDeniedAlert)
        XCTAssertEqual(poster.removeAllCount, 0)
    }

    func testToggleOnWithoutServiceRollsBack() async {
        let vm = SettingsViewModel(notifyService: nil)
        let kept = await vm.handleReminderToggle(enabled: true)
        XCTAssertFalse(kept)
        XCTAssertTrue(vm.showReminderDeniedAlert)
    }

    // MARK: - 版本号

    func testVersionReadsFromInjectedBundle() {
        let vm = SettingsViewModel(notifyService: nil, bundle: .main)
        // 测试 host 的 Info.plist 由 Xcode 生成，字段存在与否都不得为空串
        XCTAssertFalse(vm.versionMarketing.isEmpty)
        XCTAssertFalse(vm.versionBuild.isEmpty)
    }
}
