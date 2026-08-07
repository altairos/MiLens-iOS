import XCTest
@testable import MiLensKit

// EditorDocument + EditorHistory 测试。源端无专门测试文件，按模块规格编写。

final class EditorDocumentTests: XCTestCase {

    func testAddAndLayerCount() {
        let doc = EditorDocument()
        XCTAssertEqual(doc.layerCount, 0)
        var layer1 = createImageLayer(type: .photo, width: 100, height: 200)
        doc.add(&layer1)
        XCTAssertEqual(doc.layerCount, 1)
        XCTAssertEqual(doc.activeLayer?.id, layer1.id)
    }

    func testAddPassiveDoesNotChangeActive() {
        let doc = EditorDocument()
        var l1 = createImageLayer(type: .photo, width: 100, height: 200)
        var l2 = createImageLayer(type: .photo, width: 50, height: 50)
        doc.add(&l1)
        doc.addPassive(&l2)
        XCTAssertEqual(doc.layerCount, 2)
        // add 不设 active → active 仍为 l1
        XCTAssertEqual(doc.activeLayer?.id, l1.id)
    }

    func testAddPassiveSetsActiveWhenNone() {
        let doc = EditorDocument()
        var l1 = createImageLayer(type: .photo, width: 100, height: 200)
        doc.addPassive(&l1)
        // 无 active 时 addPassive 会设为 active
        XCTAssertEqual(doc.activeLayer?.id, l1.id)
    }

    func testRemoveActiveLayerFallsBack() {
        let doc = EditorDocument()
        var l1 = createImageLayer(type: .photo, width: 100, height: 200)
        var l2 = createImageLayer(type: .photo, width: 50, height: 50)
        doc.add(&l1)
        doc.add(&l2)
        XCTAssertEqual(doc.activeLayer?.id, l2.id)
        XCTAssertTrue(doc.remove(l2.id))
        XCTAssertEqual(doc.layerCount, 1)
        // 移除活动图层后回退到末尾（即 l1）
        XCTAssertEqual(doc.activeLayer?.id, l1.id)
    }

    func testRemoveNonexistentReturnsFalse() {
        let doc = EditorDocument()
        XCTAssertFalse(doc.remove("nonexistent"))
    }

    func testSelectAndClear() {
        let doc = EditorDocument()
        var l1 = createImageLayer(type: .photo, width: 100, height: 200)
        var l2 = createImageLayer(type: .photo, width: 50, height: 50)
        doc.add(&l1)
        doc.add(&l2)
        doc.select(l1.id)
        XCTAssertEqual(doc.activeLayer?.id, l1.id)
        doc.select(nil)
        XCTAssertNil(doc.activeLayer)
    }

    func testBringForward() {
        let doc = EditorDocument()
        var l1 = createImageLayer(type: .photo, width: 100, height: 200)
        var l2 = createImageLayer(type: .photo, width: 50, height: 50)
        doc.add(&l1)
        doc.add(&l2)
        // l1.zIndex=0, l2.zIndex=1 → bringForward l1 应交换
        XCTAssertTrue(doc.bringForward(l1.id))
        let layers = doc.getLayers().sorted { $0.zIndex < $1.zIndex }
        XCTAssertEqual(layers[0].id, l2.id)
        XCTAssertEqual(layers[1].id, l1.id)
    }

    func testSendBackward() {
        let doc = EditorDocument()
        var l1 = createImageLayer(type: .photo, width: 100, height: 200)
        var l2 = createImageLayer(type: .photo, width: 50, height: 50)
        doc.add(&l1)
        doc.add(&l2)
        XCTAssertTrue(doc.sendBackward(l2.id))
        let layers = doc.getLayers().sorted { $0.zIndex < $1.zIndex }
        XCTAssertEqual(layers[0].id, l2.id)
        XCTAssertEqual(layers[1].id, l1.id)
    }

    func testBringToFront() {
        let doc = EditorDocument()
        var l1 = createImageLayer(type: .photo, width: 100, height: 200)
        var l2 = createImageLayer(type: .photo, width: 50, height: 50)
        var l3 = createImageLayer(type: .photo, width: 30, height: 30)
        doc.add(&l1)
        doc.add(&l2)
        doc.add(&l3)
        XCTAssertTrue(doc.bringToFront(l1.id))
        let layers = doc.getLayers().sorted { $0.zIndex < $1.zIndex }
        XCTAssertEqual(layers.last?.id, l1.id)
    }

    func testSendToBack() {
        let doc = EditorDocument()
        var l1 = createImageLayer(type: .photo, width: 100, height: 200)
        var l2 = createImageLayer(type: .photo, width: 50, height: 50)
        var l3 = createImageLayer(type: .photo, width: 30, height: 30)
        doc.add(&l1)
        doc.add(&l2)
        doc.add(&l3)
        XCTAssertTrue(doc.sendToBack(l3.id))
        let layers = doc.getLayers().sorted { $0.zIndex < $1.zIndex }
        XCTAssertEqual(layers.first?.id, l3.id)
    }

    // MARK: - 序列化

    func testSerializeDeserializeRoundTrip() {
        let doc = EditorDocument()
        var imgLayer = createImageLayer(type: .photo, width: 200, height: 100)
        imgLayer.adjustments = EditorColorAdjustments(brightness: 10, contrast: 20)
        doc.add(&imgLayer)
        var textLayer = createTextLayer(text: "Hello", fontSize: 24)
        doc.add(&textLayer)

        guard let json = doc.serialize() else { XCTFail("serialize failed"); return }

        let doc2 = EditorDocument()
        XCTAssertTrue(doc2.restore(json))
        XCTAssertEqual(doc2.layerCount, 2)
        let restored = doc2.getLayers().sorted { $0.zIndex < $1.zIndex }
        XCTAssertEqual(restored[0].type, .photo)
        XCTAssertEqual(restored[0].width, 200)
        XCTAssertEqual(restored[0].height, 100)
        XCTAssertEqual(restored[0].adjustments.brightness, 10)
        XCTAssertEqual(restored[0].adjustments.contrast, 20)
        XCTAssertEqual(restored[1].type, .text)
        XCTAssertEqual(restored[1].text, "Hello")
        XCTAssertEqual(restored[1].fontSize, 24)
    }

    func testRestoreInvalidJsonReturnsFalse() {
        let doc = EditorDocument()
        XCTAssertFalse(doc.restore("not json"))
    }
}

final class EditorHistoryTests: XCTestCase {

    func testBasicUndoRedo() {
        let h = EditorHistory<String, String>(maxDepth: 10)
        h.initialize("state-0")
        h.push("state-1")
        h.push("state-2")

        XCTAssertEqual(h.current, "state-2")
        XCTAssertTrue(h.canUndo)

        let undoResult = h.undo()
        XCTAssertEqual(undoResult?.snapshot, "state-1")
        XCTAssertEqual(h.current, "state-1")

        XCTAssertTrue(h.canRedo)
        let redoResult = h.redo()
        XCTAssertEqual(redoResult?.snapshot, "state-2")
        XCTAssertEqual(h.current, "state-2")
    }

    func testPushClearsRedoStack() {
        let h = EditorHistory<String, String>(maxDepth: 10)
        h.initialize("s0")
        h.push("s1")
        h.undo()
        XCTAssertTrue(h.canRedo)
        h.push("s2")
        XCTAssertFalse(h.canRedo)
    }

    func testGestureCoalescing() {
        let h = EditorHistory<String, String>(maxDepth: 10)
        h.initialize("base")       // current=base, undoStack=[]
        h.push("state-1")           // undoStack=[base], current=state-1

        h.beginGesture()
        h.push("state-2")           // 手势首帧：把 state-1 入栈，undoStack=[base,state-1], current=state-2
        h.push("state-3")           // 手势续帧：只替换 current，不入栈
        h.endGesture()

        // 手势合并后 undoStack=[base, state-1]，depth=2（不是 3，因为 state-2/state-3 合并为一条）
        XCTAssertEqual(h.depth, 2)
        XCTAssertEqual(h.current, "state-3")

        // undo 回到手势前的 state-1
        let undoResult = h.undo()
        XCTAssertEqual(undoResult?.snapshot, "state-1")
        // 再 undo 回到 base
        let undoResult2 = h.undo()
        XCTAssertEqual(undoResult2?.snapshot, "base")
    }

    func testNestedBeginGestureIgnored() {
        let h = EditorHistory<String, String>(maxDepth: 10)
        h.initialize("base")
        h.beginGesture()
        h.push("s1")
        h.beginGesture()  // 嵌套：应被忽略
        h.push("s2")
        h.endGesture()    // 只结束外层一次
        // 仍在手势模式中（内层 endGesture 没有匹配），但实际设计是 endGesture 无条件结束
        // 源端行为：beginGesture 幂等，endGesture 无条件结束。所以此时已结束。
        XCTAssertFalse(h.isInGesture)
    }

    func testUndoWithoutHistoryReturnsNil() {
        let h = EditorHistory<String, String>(maxDepth: 10)
        h.initialize("only")
        XCTAssertNil(h.undo())
    }

    func testMaxDepthTrim() {
        let h = EditorHistory<String, String>(maxDepth: 3)
        h.initialize("s0")
        h.push("s1")
        h.push("s2")
        h.push("s3")
        h.push("s4")
        // 栈深度不超过 maxDepth=3
        XCTAssertLessThanOrEqual(h.depth, 3)
    }

    func testClear() {
        let h = EditorHistory<String, String>(maxDepth: 10)
        h.initialize("s0")
        h.push("s1")
        h.clear()
        XCTAssertNil(h.current)
        XCTAssertFalse(h.canUndo)
        XCTAssertFalse(h.canRedo)
    }

    func testPeekUndoRedo() {
        let h = EditorHistory<String, String>(maxDepth: 10)
        h.initialize("s0")
        h.push("s1")
        XCTAssertEqual(h.peekUndo()?.snapshot, "s0")
        h.undo()
        XCTAssertEqual(h.peekRedo()?.snapshot, "s1")
    }

    func testAttachmentPreservedThroughUndo() {
        let h = EditorHistory<String, String>(maxDepth: 10)
        h.initialize("s0", attachment: "att0")
        h.push("s1", attachment: "att1")
        XCTAssertEqual(h.currentAttach, "att1")
        h.undo()
        XCTAssertEqual(h.currentAttach, "att0")
    }
}
