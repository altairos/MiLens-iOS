import Foundation

// RedPacketHistoryLogic — 红包工作室撤销/重做纯逻辑（对应红包封面开发计划 §3.2 Phase 2）。
//
// 历史栈管理 draft 的快照序列。每次用户操作前 push 当前快照；
// 撤销 pop 到上一状态，重做反向操作。
// 纯逻辑：不持有可变状态，输入输出快照。

/// 撤销/重做状态。
public struct RedPacketHistoryState: Equatable, Sendable {
    /// 历史栈（旧→新，最后一个为当前状态）。
    public var undoStack: [RedPacketCoverDraft]
    /// 重做栈（撤销后可重做的状态，新→旧）。
    public var redoStack: [RedPacketCoverDraft]
    /// 最大历史记录数。
    public let maxHistory: Int

    public init(
        undoStack: [RedPacketCoverDraft] = [],
        redoStack: [RedPacketCoverDraft] = [],
        maxHistory: Int = 30
    ) {
        self.undoStack = undoStack
        self.redoStack = redoStack
        self.maxHistory = maxHistory
    }

    /// 是否可撤销。
    public var canUndo: Bool { undoStack.count > 1 }

    /// 是否可重做。
    public var canRedo: Bool { !redoStack.isEmpty }
}

/// 撤销/重做纯逻辑。
public enum RedPacketHistoryLogic {

    /// 创建初始历史状态（含第一帧快照）。
    public static func initialState(draft: RedPacketCoverDraft, maxHistory: Int = 30) -> RedPacketHistoryState {
        RedPacketHistoryState(undoStack: [draft], redoStack: [], maxHistory: maxHistory)
    }

    /// 在用户操作前记录快照（push 当前 draft 到 undo 栈，清空 redo）。
    public static func push(
        current: RedPacketHistoryState, draft: RedPacketCoverDraft
    ) -> RedPacketHistoryState {
        var undo = current.undoStack
        undo.append(draft)
        // 超过上限时丢弃最旧的（保留当前 + maxHistory-1 个历史）
        if undo.count > current.maxHistory {
            undo.removeFirst()
        }
        return RedPacketHistoryState(
            undoStack: undo,
            redoStack: [], // 新操作清空重做栈
            maxHistory: current.maxHistory
        )
    }

    /// 撤销：返回上一状态，把当前推入 redo 栈。
    public static func undo(_ state: RedPacketHistoryState) -> (newState: RedPacketHistoryState, restoredDraft: RedPacketCoverDraft?) {
        guard state.canUndo else { return (state, nil) }
        var undo = state.undoStack
        var redo = state.redoStack
        let current = undo.removeLast()
        redo.append(current)
        let restored = undo.last
        return (
            RedPacketHistoryState(undoStack: undo, redoStack: redo, maxHistory: state.maxHistory),
            restored
        )
    }

    /// 重做：恢复下一状态，把当前推回 undo 栈。
    public static func redo(_ state: RedPacketHistoryState) -> (newState: RedPacketHistoryState, restoredDraft: RedPacketCoverDraft?) {
        guard state.canRedo else { return (state, nil) }
        var undo = state.undoStack
        var redo = state.redoStack
        let restored = redo.removeLast()
        undo.append(restored)
        return (
            RedPacketHistoryState(undoStack: undo, redoStack: redo, maxHistory: state.maxHistory),
            restored
        )
    }
}
