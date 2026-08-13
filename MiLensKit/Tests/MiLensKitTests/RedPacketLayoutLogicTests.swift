import XCTest
@testable import MiLensKit

// RedPacketLayoutLogicTests — 布局纯逻辑测试（对应红包封面开发计划 §7 Phase 0/1 验收）。
final class RedPacketLayoutLogicTests: XCTestCase {

    private var defaultTemplate: RedPacketTemplate { RedPacketTemplateCatalog.firstFreeTemplate }

    // MARK: - 默认图层生成

    func testDefaultLayersContainsBackgroundAndForeground() {
        let layers = rpDefaultLayers(for: defaultTemplate)
        let bg = layers.first { $0.kind == .templateBackground }
        let fg = layers.first { $0.kind == .templateForeground }
        XCTAssertNotNil(bg, "应包含背景层")
        XCTAssertNotNil(fg, "应包含前景层（模板定义了 foreground）")
    }

    func testDefaultLayersContainsPetAndText() {
        let layers = rpDefaultLayers(for: defaultTemplate)
        let pet = layers.first { $0.kind == .pet }
        let text = layers.first { $0.kind == .text }
        XCTAssertNotNil(pet, "应包含 pet 占位层")
        XCTAssertNotNil(text, "应包含文本层")
    }

    func testDefaultPetLayerIsHidden() {
        let layers = rpDefaultLayers(for: defaultTemplate)
        let pet = layers.first { $0.kind == .pet }
        XCTAssertFalse(pet?.visible ?? true, "默认 pet 层应隐藏（未加载抠图）")
    }

    func testDefaultTextLayerUsesTemplateName() {
        let layers = rpDefaultLayers(for: defaultTemplate, petName: "咪咪")
        let text = layers.first { $0.kind == .text }
        XCTAssertEqual(text?.text, "咪咪")
    }

    func testDefaultTextLayerFallbackWhenNoName() {
        let layers = rpDefaultLayers(for: defaultTemplate)
        let text = layers.first { $0.kind == .text }
        XCTAssertEqual(text?.text, "恭喜发财")
    }

    func testDefaultLayersBackgroundCoversFullCanvas() {
        let layers = rpDefaultLayers(for: defaultTemplate)
        let bg = layers.first { $0.kind == .templateBackground }!
        XCTAssertEqual(bg.width, rpCanvasWidth)
        XCTAssertEqual(bg.height, rpCanvasHeight)
    }

    // MARK: - 缩放 clamp

    func testClampScaleLowerBound() {
        XCTAssertEqual(rpClampScale(0.01), RP_MIN_LAYER_SCALE)
    }

    func testClampScaleUpperBound() {
        XCTAssertEqual(rpClampScale(100), RP_MAX_LAYER_SCALE)
    }

    func testClampScaleNaN() {
        XCTAssertEqual(rpClampScale(.nan), RP_MIN_LAYER_SCALE)
    }

    func testClampScaleNormal() {
        XCTAssertEqual(rpClampScale(1.5), 1.5)
    }

    // MARK: - 位置 clamp

    func testClampPositionNormal() {
        let result = rpClampPosition(x: 400, y: 600)
        XCTAssertEqual(result.x, 400)
        XCTAssertEqual(result.y, 600)
    }

    func testClampPositionOverFlow() {
        let result = rpClampPosition(x: 9999, y: 9999)
        XCTAssertEqual(result.x, rpCanvasWidth)
        XCTAssertEqual(result.y, rpCanvasHeight)
    }

    func testClampPositionNegative() {
        let result = rpClampPosition(x: -100, y: -100)
        XCTAssertEqual(result.x, 0)
        XCTAssertEqual(result.y, 0)
    }

    // MARK: - 命中测试

    func testHitTestFindsEditableLayer() {
        let layer = makeRedPacketTextLayer(text: "测试", x: 500, y: 600, width: 200, height: 80)
        let layers = rpDefaultLayers(for: defaultTemplate) + [layer]
        let hit = rpHitTest(layers: layers, canvasX: 500, canvasY: 600)
        XCTAssertEqual(hit, layer.id)
    }

    func testHitTestReturnsNilOnEmpty() {
        let hit = rpHitTest(layers: [], canvasX: 100, canvasY: 100)
        XCTAssertNil(hit)
    }

    func testHitTestSkipsTemplateFixedLayers() {
        let layers = rpDefaultLayers(for: defaultTemplate)
        // 点击背景层中心（背景不可选）
        let hit = rpHitTest(layers: layers, canvasX: rpCanvasWidth / 2, canvasY: rpCanvasHeight / 2)
        // 只命中文本层（pet 隐藏），不命中背景
        let text = layers.first { $0.kind == .text }
        XCTAssertEqual(hit, text?.id)
    }

    func testHitTestFindsTopLayer() {
        let layer1 = makeRedPacketTextLayer(text: "底层", x: 500, y: 600, width: 200, height: 80)
        var layer2 = makeRedPacketTextLayer(text: "顶层", x: 500, y: 600, width: 200, height: 80)
        layer2.zIndex = 300
        let layers = rpDefaultLayers(for: defaultTemplate) + [layer1, layer2]
        let hit = rpHitTest(layers: layers, canvasX: 500, canvasY: 600)
        XCTAssertEqual(hit, layer2.id, "应命中 zIndex 更高的层")
    }

    func testHitTestWithRotation() {
        var layer = makeRedPacketTextLayer(text: "旋转", x: 500, y: 600, width: 200, height: 80)
        layer.rotation = 45
        // 中心点应命中（旋转不影响中心命中）
        let hit = rpHitTest(layers: [layer], canvasX: 500, canvasY: 600)
        XCTAssertEqual(hit, layer.id)
    }

    // MARK: - 模板切换（保留内容策略）

    func testSwitchTemplatePreservesPetResource() {
        var oldLayers = rpDefaultLayers(for: defaultTemplate)
        // 模拟已有 pet 资源
        if let petIdx = oldLayers.firstIndex(where: { $0.kind == .pet }) {
            var pet = oldLayers[petIdx]
            pet.resourceRef = "original_cutout.png"
            pet.visible = true
            oldLayers[petIdx] = pet
        }
        let newTemplate = RedPacketTemplateCatalog.fortuneGold
        let newLayers = rpSwitchTemplate(oldLayers: oldLayers, newTemplate: newTemplate)
        let newPet = newLayers.first { $0.kind == .pet }
        XCTAssertEqual(newPet?.resourceRef, "original_cutout.png", "切换模板应保留 pet 资源")
        XCTAssertTrue(newPet?.visible ?? false, "切换模板应保留 pet 可见状态")
    }

    func testSwitchTemplatePreservesTextContent() {
        var oldLayers = rpDefaultLayers(for: defaultTemplate, petName: "咪咪")
        let newTemplate = RedPacketTemplateCatalog.fortuneGold
        let newLayers = rpSwitchTemplate(oldLayers: oldLayers, newTemplate: newTemplate)
        let newText = newLayers.first { $0.kind == .text }
        XCTAssertEqual(newText?.text, "咪咪", "切换模板应保留文本内容")
    }

    func testSwitchTemplateUsesNewTextStyle() {
        var oldLayers = rpDefaultLayers(for: defaultTemplate, petName: "咪咪")
        let newTemplate = RedPacketTemplateCatalog.fortuneGold
        let newLayers = rpSwitchTemplate(oldLayers: oldLayers, newTemplate: newTemplate)
        let newText = newLayers.first { $0.kind == .text }
        XCTAssertEqual(newText?.styleID, newTemplate.defaultTextStylePreset.rawValue,
                       "切换模板应使用新模板的默认文本风格")
    }

    func testSwitchTemplatePreservesAccessories() {
        var oldLayers = rpDefaultLayers(for: defaultTemplate)
        var accessory = makeRedPacketTextLayer(text: "", x: 200, y: 200)
        accessory.kind = .accessory
        accessory.resourceRef = "sticker_lantern.png"
        oldLayers.append(accessory)
        let newTemplate = RedPacketTemplateCatalog.fortuneGold
        let newLayers = rpSwitchTemplate(oldLayers: oldLayers, newTemplate: newTemplate)
        let accessories = newLayers.filter { $0.kind == .accessory }
        XCTAssertEqual(accessories.count, 1, "切换模板应保留配饰")
        XCTAssertEqual(accessories.first?.resourceRef, "sticker_lantern.png")
    }

    // MARK: - 照片替换

    func testReplacePhotoUpdatesPetLayer() {
        let layers = rpDefaultLayers(for: defaultTemplate)
        let newPet = makeRedPacketPetLayer(x: 400, y: 500, resourceRef: "new_photo.png")
        let updated = rpReplacePhoto(layers: layers, newPetLayer: newPet)
        let pet = updated.first { $0.kind == .pet }
        XCTAssertEqual(pet?.resourceRef, "new_photo.png")
        XCTAssertEqual(pet?.x, 400)
        XCTAssertEqual(pet?.y, 500)
    }

    func testReplacePhotoPreservesOtherLayers() {
        let layers = rpDefaultLayers(for: defaultTemplate)
        let newPet = makeRedPacketPetLayer(x: 400, y: 500)
        let updated = rpReplacePhoto(layers: layers, newPetLayer: newPet)
        XCTAssertNotNil(updated.first { $0.kind == .templateBackground })
        XCTAssertNotNil(updated.first { $0.kind == .text })
        XCTAssertNotNil(updated.first { $0.kind == .templateForeground })
    }

    // MARK: - 安全区判定

    func testIsLayerInSafeZoneTrue() {
        let template = defaultTemplate
        let textPos = template.defaultTextPosition
        let layer = makeRedPacketTextLayer(text: "测试", x: textPos.x, y: textPos.y)
        XCTAssertTrue(rpIsLayerInSafeZone(layer, template: template))
    }

    func testIsLayerInSafeZoneFalse() {
        let template = defaultTemplate
        // 放到风险区
        let layer = makeRedPacketTextLayer(
            text: "测试", x: rpCanvasWidth / 2, y: rpCanvasHeight * 0.95
        )
        XCTAssertFalse(rpIsLayerInSafeZone(layer, template: template))
    }

    func testCanvasVisibleRatioDetectsClippedLayer() {
        let layer = makeRedPacketPetLayer(
            x: 30, y: rpCanvasHeight / 2, width: 300, height: 300
        )
        let ratio = rpLayerCanvasVisibleRatio(layer)
        XCTAssertLessThan(ratio, 0.7)
        XCTAssertGreaterThan(ratio, 0)
    }

    func testSafeZoneCoverageUsesWholeRotatedBounds() {
        var layer = makeRedPacketPetLayer(
            x: defaultTemplate.defaultPetTransform.x,
            y: defaultTemplate.defaultPetTransform.y,
            width: 300,
            height: 300
        )
        let centered = rpLayerSafeZoneCoverageRatio(layer, template: defaultTemplate)
        layer.rotation = 45
        let rotated = rpLayerSafeZoneCoverageRatio(layer, template: defaultTemplate)

        XCTAssertEqual(centered, 1, accuracy: 0.001)
        XCTAssertLessThanOrEqual(rotated, centered)
    }

    // MARK: - 图层操作

    func testCenterLayer() {
        let layer = makeRedPacketTextLayer(text: "测试", x: 100, y: 100)
        let centered = rpCenterLayer(layer)
        XCTAssertEqual(centered.x, rpCanvasWidth / 2)
        XCTAssertEqual(centered.y, rpCanvasHeight / 2)
    }

    func testResetLayerToDefaultText() {
        let template = defaultTemplate
        let textPos = template.defaultTextPosition
        var layer = makeRedPacketTextLayer(text: "测试", x: textPos.x, y: textPos.y)
        layer.x = 1
        layer.y = 1
        layer.scale = 3
        let reset = rpResetLayerToDefault(layer, template: template)
        XCTAssertEqual(reset.x, textPos.x)
        XCTAssertEqual(reset.y, textPos.y)
        XCTAssertEqual(reset.scale, 1.0)
    }

    func testDeleteLayerRemovesEditable() {
        let textLayer = makeRedPacketTextLayer(text: "测试", x: 500, y: 600)
        let layers = rpDefaultLayers(for: defaultTemplate) + [textLayer]
        let afterDelete = rpDeleteLayer(layers, id: textLayer.id)
        XCTAssertNil(afterDelete.first { $0.id == textLayer.id })
    }

    func testDeleteLayerDoesNotRemoveTemplateFixed() {
        let layers = rpDefaultLayers(for: defaultTemplate)
        let bg = layers.first { $0.kind == .templateBackground }!
        let afterDelete = rpDeleteLayer(layers, id: bg.id)
        XCTAssertNotNil(afterDelete.first { $0.id == bg.id }, "模板固定层不应被删除")
    }

    func testUpdateLayerModifiesTarget() {
        let layer = makeRedPacketTextLayer(text: "原", x: 500, y: 600)
        let layers = [layer]
        let updated = rpUpdateLayer(layers, id: layer.id) { $0.text = "改" }
        XCTAssertEqual(updated.first?.text, "改")
    }
}
