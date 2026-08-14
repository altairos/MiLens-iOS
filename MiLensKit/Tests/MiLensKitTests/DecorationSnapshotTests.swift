import XCTest
@testable import MiLensKit

// DecorationSnapshotTests — 快照 resourcePath/visible 字段扩展测试（阻塞项1）。
// 覆盖：frame/sticker 层携带 resourcePath、photo/text 层不携带；visible 往返；
// 旧 JSON（缺 resourcePath/visible key，源端/历史存量格式）decode 容错。

final class DecorationSnapshotTests: XCTestCase {

    // MARK: - 序列化写入

    func testFrameSnapshotCarriesResourcePathAndVisible() {
        let layer = createImageLayer(
            type: .frame, width: 300, height: 400,
            resourcePath: "frame_polaroid", x: 150, y: 200)
        let snapshot = serializeEditorLayer(layer)
        XCTAssertEqual(snapshot.resourcePath, "frame_polaroid")
        XCTAssertEqual(snapshot.visible, true)
    }

    func testStickerSnapshotCarriesResourcePath() {
        let layer = createImageLayer(
            type: .sticker, width: 44, height: 44,
            resourcePath: "sticker_paw", x: 136, y: 164)
        let snapshot = serializeEditorLayer(layer)
        XCTAssertEqual(snapshot.resourcePath, "sticker_paw")
    }

    func testPhotoSnapshotOmitsResourcePath() throws {
        // photo 层 resourcePath 恒 nil（不写入 JSON），visible 恒写入
        let layer = createImageLayer(type: .photo, width: 100, height: 100)
        let snapshot = serializeEditorLayer(layer)
        XCTAssertNil(snapshot.resourcePath)
        XCTAssertEqual(snapshot.visible, true)
        let json = try JSONEncoder().encode([snapshot])
        let str = try XCTUnwrap(String(data: json, encoding: .utf8))
        XCTAssertFalse(str.contains("\"resourcePath\""), "nil 可选字段不应输出 key")
        XCTAssertTrue(str.contains("\"visible\""), "visible 对所有层写入")
    }

    func testTextSnapshotOmitsResourcePath() {
        let layer = createTextLayer(text: "hi", x: 50, y: 60)
        XCTAssertNil(serializeEditorLayer(layer).resourcePath)
    }

    // MARK: - 反序列化恢复

    func testHiddenDecorationLayerRoundTrip() {
        // 隐藏的装饰层：visible=false 经序列化往返保持
        var layer = createImageLayer(
            type: .sticker, width: 44, height: 44, resourcePath: "s1")
        layer.visible = false
        let restored = deserializeEditorLayer(serializeEditorLayer(layer))
        XCTAssertFalse(restored.visible)
        XCTAssertEqual(restored.resourcePath, "s1")
        XCTAssertEqual(restored.type, .sticker)
    }

    func testDocumentRoundTripPreservesDecorationFields() throws {
        // 文档级 JSON 往返：resourcePath/visible 不丢
        let doc = EditorDocument()
        var frame = createImageLayer(
            type: .frame, width: 300, height: 400,
            resourcePath: "frame_x", x: 150, y: 200)
        doc.addPassive(&frame)
        var sticker = createImageLayer(
            type: .sticker, width: 44, height: 44, resourcePath: "sticker_y")
        sticker.visible = false
        doc.add(&sticker)

        let json = try XCTUnwrap(doc.serialize())
        let restored = EditorDocument()
        XCTAssertTrue(restored.restore(json))
        let layers = restored.getLayers()
        XCTAssertEqual(layers.count, 2)
        XCTAssertEqual(layers[0].resourcePath, "frame_x")
        XCTAssertEqual(layers[1].resourcePath, "sticker_y")
        XCTAssertFalse(layers[1].visible)
    }

    // MARK: - 旧 JSON 容错（缺新增 key）

    func testOldJsonWithoutNewFieldsDecodes() throws {
        // 源端/历史快照格式：无 resourcePath、无 visible key → 成功恢复，默认可见、路径空串
        let json = """
        [{"id":"p1","type":"photo","x":50,"y":100,"width":100,"height":200,
          "rotation":0,"scale":1,"opacity":1,"zIndex":0,"flipX":false,"flipY":false,
          "brightness":0,"contrast":0,"saturation":0,"temperature":0,"sharpness":0,
          "text":"","fontSize":32,"fontColor":"#FFFFFF","maxWidth":400,
          "strokeWidth":2,"strokeColor":"#000000","hasAlpha":false}]
        """
        let doc = EditorDocument()
        XCTAssertTrue(doc.restore(json))
        let layer = try XCTUnwrap(doc.getLayers().first)
        XCTAssertEqual(layer.visible, true, "缺 visible key 默认可见")
        XCTAssertEqual(layer.resourcePath, "", "缺 resourcePath key 回退空串")
    }
}
