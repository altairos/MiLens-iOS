import XCTest
@testable import MiLensKit

// RedPacketHistoryLogicTests — 撤销/重做纯逻辑测试（对应红包封面开发计划 §3.2 Phase 2）。
final class RedPacketHistoryLogicTests: XCTestCase {

    private var defaultTemplate: RedPacketTemplate { RedPacketTemplateCatalog.firstFreeTemplate }

    // MARK: - 初始状态

    func testInitialStateCanNotUndo() {
        let draft = RedPacketCoverDraft.create(from: defaultTemplate, petName: "咪咪")
        let state = RedPacketHistoryLogic.initialState(draft: draft)
        XCTAssertFalse(state.canUndo, "初始状态不可撤销")
        XCTAssertFalse(state.canRedo, "初始状态不可重做")
    }

    // MARK: - push

    func testPushEnablesUndo() {
        let draft = RedPacketCoverDraft.create(from: defaultTemplate, petName: "咪咪")
        var state = RedPacketHistoryLogic.initialState(draft: draft)

        var modified = draft
        modified.petName = "小橘"
        state = RedPacketHistoryLogic.push(current: state, draft: modified)

        XCTAssertTrue(state.canUndo, "push 后应可撤销")
    }

    func testPushClearsRedoStack() {
        let draft = RedPacketCoverDraft.create(from: defaultTemplate, petName: "咪咪")
        var state = RedPacketHistoryLogic.initialState(draft: draft)

        // push → undo → push 应清空 redo
        var v2 = draft; v2.petName = "V2"
        state = RedPacketHistoryLogic.push(current: state, draft: v2)
        state = RedPacketHistoryLogic.undo(state).newState
        XCTAssertTrue(state.canRedo)

        var v3 = draft; v3.petName = "V3"
        state = RedPacketHistoryLogic.push(current: state, draft: v3)
        XCTAssertFalse(state.canRedo, "新 push 应清空 redo 栈")
    }

    // MARK: - undo

    func testUndoRestoresPreviousDraft() {
        let original = RedPacketCoverDraft.create(from: defaultTemplate, petName: "咪咪")
        var state = RedPacketHistoryLogic.initialState(draft: original)

        var modified = original
        modified.petName = "小橘"
        state = RedPacketHistoryLogic.push(current: state, draft: modified)

        let (newState, restored) = RedPacketHistoryLogic.undo(state)
        XCTAssertEqual(restored?.petName, "咪咪", "undo 应恢复到原始草稿")
        XCTAssertTrue(newState.canRedo, "undo 后应可重做")
    }

    func testUndoWhenNotPossibleReturnsNil() {
        let draft = RedPacketCoverDraft.create(from: defaultTemplate, petName: "咪咪")
        let state = RedPacketHistoryLogic.initialState(draft: draft)
        let (newState, restored) = RedPacketHistoryLogic.undo(state)
        XCTAssertNil(restored)
        XCTAssertEqual(newState.undoStack.count, state.undoStack.count)
    }

    // MARK: - redo

    func testRedoRestoresUndoneDraft() {
        let original = RedPacketCoverDraft.create(from: defaultTemplate, petName: "咪咪")
        var state = RedPacketHistoryLogic.initialState(draft: original)

        var modified = original
        modified.petName = "小橘"
        state = RedPacketHistoryLogic.push(current: state, draft: modified)

        // undo
        state = RedPacketHistoryLogic.undo(state).newState
        // redo
        let (newState, restored) = RedPacketHistoryLogic.redo(state)
        XCTAssertEqual(restored?.petName, "小橘", "redo 应恢复到修改后草稿")
    }

    func testRedoWhenNotPossibleReturnsNil() {
        let draft = RedPacketCoverDraft.create(from: defaultTemplate, petName: "咪咪")
        let state = RedPacketHistoryLogic.initialState(draft: draft)
        let (newState, restored) = RedPacketHistoryLogic.redo(state)
        XCTAssertNil(restored)
    }

    // MARK: - 多步操作

    func testMultiplePushAndUndo() {
        let original = RedPacketCoverDraft.create(from: defaultTemplate, petName: "V1")
        var state = RedPacketHistoryLogic.initialState(draft: original)

        for i in 2...5 {
            var v = original
            v.petName = "V\(i)"
            state = RedPacketHistoryLogic.push(current: state, draft: v)
        }

        // 连续 undo 4 次回到 V1
        for step in stride(from: 4, through: 1, by: -1) {
            let (newState, restored) = RedPacketHistoryLogic.undo(state)
            state = newState
            XCTAssertEqual(restored?.petName, "V\(step)")
        }
    }

    // MARK: - 上限

    func testMaxHistoryLimit() {
        let original = RedPacketCoverDraft.create(from: defaultTemplate, petName: "V0")
        var state = RedPacketHistoryLogic.initialState(draft: original, maxHistory: 3)

        for i in 1...10 {
            var v = original
            v.petName = "V\(i)"
            state = RedPacketHistoryLogic.push(current: state, draft: v)
        }

        XCTAssertLessThanOrEqual(state.undoStack.count, 3, "undo 栈不应超过 maxHistory")
    }

    // MARK: - undo → undo → redo → redo 序列

    func testUndoRedoSequence() {
        let original = RedPacketCoverDraft.create(from: defaultTemplate, petName: "V1")
        var state = RedPacketHistoryLogic.initialState(draft: original)

        var v2 = original; v2.petName = "V2"
        state = RedPacketHistoryLogic.push(current: state, draft: v2)

        var v3 = original; v3.petName = "V3"
        state = RedPacketHistoryLogic.push(current: state, draft: v3)

        // undo → V2
        state = RedPacketHistoryLogic.undo(state).newState
        XCTAssertEqual(state.undoStack.last?.petName, "V2")

        // undo → V1
        state = RedPacketHistoryLogic.undo(state).newState
        XCTAssertEqual(state.undoStack.last?.petName, "V1")

        // redo → V2
        state = RedPacketHistoryLogic.redo(state).newState
        XCTAssertEqual(state.undoStack.last?.petName, "V2")

        // redo → V3
        state = RedPacketHistoryLogic.redo(state).newState
        XCTAssertEqual(state.undoStack.last?.petName, "V3")
    }
}
