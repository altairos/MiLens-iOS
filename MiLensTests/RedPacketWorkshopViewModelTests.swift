//  RedPacketWorkshopViewModelTests — 工作室 ViewModel 状态机测试。
//
//  验证：选中/移动/删除/切模板（含 Pro 权限拦截）/文本编辑撤销会话/加载失败态/草稿保存恢复。
//  抠图状态机用 MockVisionService 验证（无真实 Vision 框架依赖）。
//  注意：UIKit (UIImage) 在非 macOS/Linux 测试环境不可用，本测试需 macOS/Xcode 执行。

import XCTest
@testable import MiLens
import MiLensKit

@MainActor
final class RedPacketWorkshopViewModelTests: XCTestCase {

    // MARK: - 工厂

    private func makeVM(
        template: RedPacketTemplate = RedPacketTemplateCatalog.firstFreeTemplate,
        templateID: String? = nil,
        isPro: Bool = false
    ) -> RedPacketWorkshopViewModel {
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository()
        let vision = MockVisionService()
        let draftStore = RedPacketDraftStore()
        return RedPacketWorkshopViewModel(
            templateID: templateID ?? template.id,
            photoID: UUID(),
            petID: nil,
            isPro: isPro,
            photoRepo: photoRepo,
            petRepo: petRepo,
            vision: vision,
            draftStore: draftStore,
            imageQualityAnalyzer: CoreGraphicsRedPacketImageQualityAnalyzer()
        )
    }

    // MARK: - 初始化

    func testInitialState() {
        let vm = makeVM()
        XCTAssertTrue(vm.isLoading)
        XCTAssertEqual(vm.template.id, RedPacketTemplateCatalog.firstFreeTemplate.id)
        XCTAssertTrue(vm.layers.isEmpty)
        XCTAssertNil(vm.activeLayerID)
        XCTAssertEqual(vm.cutoutPhase, .idle)
    }

    // MARK: - 图层操作（手动设置草稿）

    func testSelectLayerByText() {
        let vm = makeVM()
        let template = vm.template
        vm.draft = RedPacketCoverDraft.create(from: template, petName: "咪咪")

        // 选中文本层（点击文本层中心）
        let textLayer = vm.layers.first { $0.kind == .text }!
        vm.selectLayer(at: CGPoint(x: textLayer.x, y: textLayer.y))
        XCTAssertEqual(vm.activeLayerID, textLayer.id)
    }

    func testDeselect() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        let textLayer = vm.layers.first { $0.kind == .text }!
        vm.activeLayerID = textLayer.id
        vm.deselect()
        XCTAssertNil(vm.activeLayerID)
    }

    func testMoveActive() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        let textLayer = vm.layers.first { $0.kind == .text }!
        vm.activeLayerID = textLayer.id
        let originalX = textLayer.x
        vm.moveActive(dx: 50, dy: 30)
        let updated = vm.layers.first { $0.kind == .text }!
        XCTAssertEqual(updated.x, originalX + 50, accuracy: 0.1)
    }

    func testScaleActive() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        let textLayer = vm.layers.first { $0.kind == .text }!
        vm.activeLayerID = textLayer.id
        vm.scaleActive(by: 1.5)
        let updated = vm.layers.first { $0.kind == .text }!
        XCTAssertEqual(updated.scale, 1.5, accuracy: 0.01)
    }

    func testRotateActive() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        let textLayer = vm.layers.first { $0.kind == .text }!
        vm.activeLayerID = textLayer.id
        vm.rotateActive(by: 45)
        let updated = vm.layers.first { $0.kind == .text }!
        XCTAssertEqual(updated.rotation, 45, accuracy: 0.1)
    }

    func testScaleClamp() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        let textLayer = vm.layers.first { $0.kind == .text }!
        vm.activeLayerID = textLayer.id
        vm.scaleActive(by: 0.001) // 极小值
        let updated = vm.layers.first { $0.kind == .text }!
        XCTAssertEqual(updated.scale, RP_MIN_LAYER_SCALE, accuracy: 0.001)
    }

    // MARK: - 删除

    func testDeleteActive() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        let textLayer = vm.layers.first { $0.kind == .text }!
        let layerCountBefore = vm.layers.count
        vm.activeLayerID = textLayer.id
        vm.deleteActive()
        XCTAssertEqual(vm.layers.count, layerCountBefore - 1)
        XCTAssertNil(vm.activeLayerID)
    }

    // MARK: - 居中/恢复

    func testCenterActive() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        let textLayer = vm.layers.first { $0.kind == .text }!
        vm.activeLayerID = textLayer.id
        vm.centerActive()
        let updated = vm.layers.first { $0.kind == .text }!
        XCTAssertEqual(updated.x, rpCanvasWidth / 2, accuracy: 0.1)
        XCTAssertEqual(updated.y, rpCanvasHeight / 2, accuracy: 0.1)
    }

    func testResetActive() {
        let vm = makeVM()
        let template = vm.template
        vm.draft = RedPacketCoverDraft.create(from: template, petName: "咪咪")
        let textLayer = vm.layers.first { $0.kind == .text }!
        vm.activeLayerID = textLayer.id
        // 先移动
        vm.moveActive(dx: 100, dy: 100)
        vm.scaleActive(by: 3)
        // 再恢复
        vm.resetActive()
        let updated = vm.layers.first { $0.kind == .text }!
        XCTAssertEqual(updated.x, template.defaultTextPosition.x, accuracy: 0.1)
        XCTAssertEqual(updated.y, template.defaultTextPosition.y, accuracy: 0.1)
        XCTAssertEqual(updated.scale, 1.0)
    }

    // MARK: - 文本编辑

    func testUpdateText() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        vm.updateText("发财")
        let textLayer = vm.layers.first { $0.kind == .text }!
        XCTAssertEqual(textLayer.text, "发财")
        XCTAssertEqual(vm.draft.coverTitle, "发财")
    }

    func testUpdateTextTruncation() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        vm.updateText("这是一段超长的文本内容测试截断")
        let textLayer = vm.layers.first { $0.kind == .text }!
        XCTAssertLessThanOrEqual(textLayer.text.count, WeChatRedPacketSpec.coverTitleMaxLength)
    }

    func testUpdateTextPushesSingleSnapshotPerSession() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        vm.updateText("新")
        vm.updateText("新年")
        vm.updateText("新年好")
        XCTAssertEqual(vm.history.undoStack.count, 1, "同一输入会话内连续键入只记一条撤销快照")
        vm.endTextEdit()
        vm.updateText("发大财")
        XCTAssertEqual(vm.history.undoStack.count, 2, "会话结束后再次输入开启新撤销记录")
        vm.undo()
        XCTAssertEqual(vm.layers.first { $0.kind == .text }?.text, "新年好")
    }

    // MARK: - 模板切换

    func testSwitchTemplatePreservesText() {
        let vm = makeVM(isPro: true)
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        vm.updateText("新年好")
        vm.switchTemplate(to: RedPacketTemplateCatalog.fortuneGold.id)
        let textLayer = vm.layers.first { $0.kind == .text }
        XCTAssertEqual(textLayer?.text, "新年好")
    }

    func testSwitchTemplateUpdatesTemplateID() {
        let vm = makeVM(isPro: true)
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        vm.switchTemplate(to: RedPacketTemplateCatalog.fortuneGold.id)
        XCTAssertEqual(vm.draft.templateID, RedPacketTemplateCatalog.fortuneGold.id)
    }

    func testSwitchTemplateBlockedWithoutPro() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        let draftBefore = vm.draft
        vm.switchTemplate(to: RedPacketTemplateCatalog.fortuneGold.id)
        // 非 Pro 不可越权切到付费模板（View 层 isLocked 之外的 VM 层兜底）
        XCTAssertEqual(vm.draft.templateID, RedPacketTemplateCatalog.newYearRed.id)
        XCTAssertEqual(vm.draft, draftBefore)
        XCTAssertFalse(vm.canUndo, "被拦截的切换不应推撤销快照")
    }

    func testSwitchTemplateUnknownIDIgnored() {
        let vm = makeVM(isPro: true)
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        vm.switchTemplate(to: "no_such_template")
        XCTAssertEqual(vm.draft.templateID, RedPacketTemplateCatalog.newYearRed.id)
    }

    // MARK: - 草稿保存/恢复

    func testSaveDraftReturnsID() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        let id = vm.saveDraft()
        XCTAssertEqual(id, vm.draft.id)
    }

    func testActiveLayerIsCorrect() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        let textLayer = vm.layers.first { $0.kind == .text }!
        vm.activeLayerID = textLayer.id
        XCTAssertEqual(vm.activeLayer?.id, textLayer.id)
    }

    func testActiveLayerNilWhenNotSelected() {
        let vm = makeVM()
        vm.draft = RedPacketCoverDraft.create(from: vm.template, petName: "咪咪")
        XCTAssertNil(vm.activeLayer)
    }

    // MARK: - 加载失败态

    func testLoadInvalidTemplateSetsError() async {
        let vm = makeVM(templateID: "no_such_template")
        await vm.load()
        XCTAssertEqual(vm.loadError, .templateNotFound)
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadMissingPhotoSetsError() async {
        let vm = makeVM()
        await vm.load()
        XCTAssertEqual(vm.loadError, .photoNotFound)
        XCTAssertFalse(vm.isLoading)
    }
}
