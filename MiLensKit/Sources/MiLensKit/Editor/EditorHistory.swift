import Foundation

// EditorHistory — 编辑器通用撤销/重做历史栈（含手势合并）。
// 翻译自源端 entry/.../editor/EditorHistory.ets（156 行）。
//
// 纯逻辑：不含 ArkUI / PixelMap 依赖。泛型 T 为快照类型（通常是不变值或 JSON 字符串），
// 泛型 A 为附件类型（可选，用于关联运行时资源恢复引用）。

/// 历史栈条目。对应源端 `HistoryEntry`。
public struct EditorHistoryEntry<T, A>: Equatable where T: Equatable, A: Equatable {
    public var snapshot: T
    public var attachment: A?

    public init(snapshot: T, attachment: A? = nil) {
        self.snapshot = snapshot; self.attachment = attachment
    }
}

/// 编辑器通用历史栈。对应源端 `EditorHistory<T, A>`。
///
/// 手势合并（coalescing）：beginGesture/endGesture 之间的连续 push 只产生一条历史。
/// 用法示例：
/// ```
/// let h = EditorHistory<String, String>(maxDepth: 30)
/// h.initialize("state-0")
/// h.push("state-1")       // undoStack=["state-0"], current="state-1"
/// h.beginGesture()
/// h.push("state-2")       // 手势首帧：把 "state-1" 入栈，current="state-2"
/// h.push("state-3")       // 手势续帧：只替换 current，不入栈
/// h.endGesture()
/// h.undo()                // 返回 "state-1"
/// ```
public final class EditorHistory<T: Equatable, A: Equatable> {

    private var undoStack: [EditorHistoryEntry<T, A>] = []
    private var redoStack: [EditorHistoryEntry<T, A>] = []
    private var currentSnapshot: T?
    private var currentAttachment: A?
    private let maxDepth: Int
    private var gestureActive = false
    private var gestureBaselinePushed = false

    public init(maxDepth: Int = 30) {
        self.maxDepth = max(1, maxDepth)
    }

    /// 初始化当前快照，清空两个栈。
    public func initialize(_ snapshot: T, attachment: A? = nil) {
        currentSnapshot = snapshot
        currentAttachment = attachment
        undoStack.removeAll()
        redoStack.removeAll()
        gestureActive = false
        gestureBaselinePushed = false
    }

    /// 当前快照（nil 表示未 initialize）。
    public var current: T? { currentSnapshot }

    /// 当前附件。
    public var currentAttach: A? { currentAttachment }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// undo 栈深度（不含当前快照）。
    public var depth: Int { undoStack.count }

    /// 提交新快照。
    /// - 普通模式：把当前快照入 undoStack，新快照成为 current，清空 redoStack。
    /// - 手势模式：手势首帧把当前快照入栈，后续帧只替换 current（实现"连续调整合并为一条历史"）。
    public func push(_ snapshot: T, attachment: A? = nil) {
        guard currentSnapshot != nil else {
            currentSnapshot = snapshot
            currentAttachment = attachment
            return
        }
        if gestureActive {
            if !gestureBaselinePushed {
                undoStack.append(EditorHistoryEntry(snapshot: currentSnapshot!, attachment: currentAttachment))
                trimUndoStack()
                redoStack.removeAll()
                gestureBaselinePushed = true
            }
        } else {
            undoStack.append(EditorHistoryEntry(snapshot: currentSnapshot!, attachment: currentAttachment))
            trimUndoStack()
            redoStack.removeAll()
        }
        currentSnapshot = snapshot
        currentAttachment = attachment
    }

    /// 开启手势合并模式。
    public func beginGesture() {
        if gestureActive { return }
        gestureActive = true
        gestureBaselinePushed = false
    }

    /// 结束手势合并模式。
    public func endGesture() {
        gestureActive = false
        gestureBaselinePushed = false
    }

    /// 当前是否在手势合并模式中。
    public var isInGesture: Bool { gestureActive }

    /// 撤销：把当前快照压入 redoStack，弹出 undoStack 栈顶作为新 current。
    @discardableResult
    public func undo() -> EditorHistoryEntry<T, A>? {
        guard !undoStack.isEmpty else { return nil }
        if let cur = currentSnapshot {
            redoStack.append(EditorHistoryEntry(snapshot: cur, attachment: currentAttachment))
        }
        let prev = undoStack.removeLast()
        currentSnapshot = prev.snapshot
        currentAttachment = prev.attachment
        return prev
    }

    /// 重做：把当前快照压入 undoStack，弹出 redoStack 栈顶作为新 current。
    @discardableResult
    public func redo() -> EditorHistoryEntry<T, A>? {
        guard !redoStack.isEmpty else { return nil }
        if let cur = currentSnapshot {
            undoStack.append(EditorHistoryEntry(snapshot: cur, attachment: currentAttachment))
            trimUndoStack()
        }
        let next = redoStack.removeLast()
        currentSnapshot = next.snapshot
        currentAttachment = next.attachment
        return next
    }

    /// 清空两个栈与当前快照。
    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        currentSnapshot = nil
        currentAttachment = nil
        gestureActive = false
        gestureBaselinePushed = false
    }

    /// 查看 undo 栈顶（只读，不入栈/出栈）。
    public func peekUndo() -> EditorHistoryEntry<T, A>? {
        undoStack.last
    }

    /// 查看 redo 栈顶。
    public func peekRedo() -> EditorHistoryEntry<T, A>? {
        redoStack.last
    }

    private func trimUndoStack() {
        while undoStack.count > maxDepth {
            undoStack.removeFirst()
        }
    }
}
