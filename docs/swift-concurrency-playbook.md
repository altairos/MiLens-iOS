# Swift 并发陷阱手册

本手册记录 iOS 26.5 + Swift Concurrency 已踩过的确定性陷阱与定位路径。
**跨机器协作参考**：不依赖任何 AI 会话上下文，只依赖仓库本身。

与 [swiftdata-crash-playbook.md](swiftdata-crash-playbook.md) 并列：那本专治
SwiftData 持久化层崩溃，本本专治 `async/await` / `Continuation` / `Task` 取消语义。

---

## 陷阱 1：`onCancel` 不恢复 continuation → 任务永久挂起

### 症状

- 某个 `async` 方法在「任务被取消」后**永远不返回**，`try await task.value` 卡死；
- 表现为单个 XCTest 不结束，`xcodebuild test` 整体挂住、必须手动 kill；
- 崩溃栈看不到应用帧——因为根本没崩，是 continuation 泄漏。

典型触发：把回调式系统 API（`PHImageManager` / Vision / `URLSession` 旧式 delegate /
`CGImageSource` 等）用 `withTaskCancellationHandler` + `withCheckedThrowingContinuation`
桥接为 `async`。

### 根因：`onCancel` 只取消底层请求，不恢复 continuation

错误写法（**只 cancel，不 resume**）：

```swift
func loadOriginalData(_ asset: PHAsset) async throws -> Data {
    let box = RequestIDBox()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            box.set(manager.requestImageDataAndOrientation(for: asset, options: nil) { ... in
                // 结果回调里 resume continuation
            }, manager: manager)
        }
    } onCancel: {
        // ❌ 只取消了底层请求，没有 resume continuation
        box.cancel(manager: manager)
    }
}
```

这隐式假设「取消底层请求后，API 必然回调 `PHImageCancelledKey` 之类来恢复 continuation」。
该假设**不成立**：

1. 测试里的 fake manager，`cancelImageRequest` 往往只记录 ID、不触发回调
   → continuation 永远不被恢复 → `await` 永久挂起；
2. 即便生产环境，回调式 API 在极端时序下也可能不回调。

关键事实：`withCheckedThrowingContinuation` **不像** `withUnsafeContinuation`
会随任务取消自动恢复——必须显式 `resume`，否则泄漏一个永不完成的 continuation。
"取消"在 Swift 并发里是协作式的，`onCancel` 是你收尾的唯一确定时机。

### 判别方法

- 任务 `cancel()` 后，`try await task.value` 永不返回 → 基本就是本症；
- 二分定位：把 fake manager 的 `cancelImageRequest` 改成"取消后立刻触发一次
  `PHImageCancelledKey: true` 回调"，若测试突然能结束 → 实现依赖了回调，
  属于本陷阱（即便能跑也不健壮）。

### 修复模式：`onCancel` 必须自己 resume continuation

让 `onCancel` 在取消底层请求的同时**主动把 continuation resume 为
`CancellationError`**，并用「单次恢复权」保护，避免与结果回调二次 resume 冲突。
MiLens 的做法（`IOSPhotoLibraryAccess.RequestIDBox`）：

1. `RequestIDBox` 增加 `registerCancelResume(_:)`：登记"resume continuation 为
   `CancellationError`"的动作；若取消已先到（墓碑已置位），登记时立即执行；
2. `cancel(manager:)` 在 `cancelImageRequest` 之后执行该动作；
3. 取消恢复与结果回调**共用同一个 `beginResume()` 锁保护的单次标志**，
   谁先到都只 resume 一次，另一个自动作废；
4. 用专用静态辅助 `resumeCancellation<Value>(_ box:, _ continuation:)` 触发取消恢复
   （只从 continuation 一个参数推断泛型 `Value`，避免多参泛型推断失败）。

骨架（完整实现见代码位置）：

```swift
final class RequestIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var resumed = false
    private var onCancelResume: (() -> Void)?

    /// 登记取消恢复动作；取消已先到则立即执行。
    func registerCancelResume(_ action: @escaping () -> Void) {
        lock.lock(); let alreadyCancelled = isCancelled
        if !alreadyCancelled { onCancelResume = action }
        lock.unlock()
        if alreadyCancelled { action() }
    }

    /// 取消底层请求 + 恢复 continuation（不依赖 API 回调）。
    func cancel(manager: any PHImageRequesting) {
        lock.lock(); isCancelled = true
        let current = id; let resume = onCancelResume; onCancelResume = nil
        lock.unlock()
        if current != PHInvalidImageRequestID { manager.cancelImageRequest(current) }
        resume?()   // ← 关键：主动收尾
    }

    /// 单次恢复权：与结果回调互斥，防二次 resume 崩溃。
    func beginResume() -> Bool { /* lock + resumed 判定 */ }
}
```

桥接侧（`loadOriginalData` / `loadScaledImage`）拿到 continuation 后立刻登记：

```swift
try await withCheckedThrowingContinuation { continuation in
    box.registerCancelResume { Self.resumeCancellation(box, continuation) }
    box.set(manager.requestImageDataAndOrientation(...) { ..., info in
        Self.resumeIfNeeded(box, continuation, outcome)   // 结果回调路径
    }, manager: manager)
}
```

### 适用边界

- **适用**：所有把回调式 / delegate 式系统 API 桥接为 `async`，且用
  `withTaskCancellationHandler` 做协作取消的场景。
- **不适用**：本身已是 `async throws` 且支持协作取消的 API
  （`Task.sleep`、`URLSession.data(for:)` 等）——它们被取消时自动抛
  `CancellationError`，无需手动 resume。

---

## 快速自查清单

遇到「任务取消后 `await` 永不返回 / 单测卡死」时按此顺序排查：

1. **是不是 `onCancel` 没 resume continuation？**（搜
   `withTaskCancellationHandler` + `withCheckedThrowingContinuation`，
   看 `onCancel` 里是否只有 cancel、没有 resume）
2. **是不是 fake manager 不回调？**（测试侧 `cancelImageRequest` 只记录 ID
   不触发回调 → 暴露实现侧的隐式假设）
3. **resume 是否有单次保护？**（取消恢复与结果回调必须共用 `beginResume()`，
   否则二次 resume 会崩 `Swift task continuation misuse`）
4. **泛型推断是否失败？**（取消恢复闭包若传多参数泛型，编译器可能报
   `Generic parameter 'T' could not be inferred` —— 用只依赖 continuation
   单参的专用辅助方法，或在调用处显式标注返回类型）

---

## 相关代码位置

- `MiLens/Services/Platform/IOSPhotoLibraryAccess.swift`
  - `loadOriginalData` / `loadScaledImage` —— 桥接 + 取消恢复登记
  - `RequestIDBox.registerCancelResume` / `cancel(manager:)` —— 取消墓碑 + 主动恢复
  - `RequestIDBox.beginResume()` —— 单次恢复权
  - `IOSPhotoLibraryAccess.resumeCancellation(...)` —— 取消恢复专用辅助
- `MiLensTests/IOSPhotoLibraryAccessTests.swift`
  - `testCancelledTaskCancelsPendingRequest` —— 守护本陷阱不再回归
