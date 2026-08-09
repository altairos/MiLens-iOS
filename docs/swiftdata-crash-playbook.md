# SwiftData 崩溃排查手册

本手册记录 iOS 26.5 + SwiftData 已踩过的确定性崩溃类型与定位路径。
**跨机器协作参考**：不依赖任何 AI 会话上下文，只依赖仓库本身。

---

## 原则：先确认是不是"既有问题"

再跑一次修改前的版本（`git stash` 当前改动 → 跑测试 → `git stash pop`），
若崩溃集合**不变**，则是既有问题，不要把锅扣在自己这次改动上。
定位既有的、确定性的崩溃比"证明我没改坏"更有价值。

---

## 崩溃 1：SIGTRAP on `context.save` / `context.fetch`（最常见）

### 症状

```
exception: EXC_BREAKPOINT / SIGTRAP, rawCodes [1, <同一数字>]
triggered thread: SwiftData + <offset>
  → MiLens.debug.dylib SwiftDataPhotoRepository.insertPhoto(_:) PhotoRepository.swift:164
  → PhotoRepositoryTests.testInsertAndFetchById()
```

- 崩在 SwiftData 框架内部（堆栈顶端是 SwiftData，没有应用代码帧）。
- `rawCodes[1]` 多次运行**完全相同** → 确定性断言失败。
- xcodebuild 输出："Restarting after unexpected exit, crash, or test timeout"。
- 最终 MiLensTests.xctest 报 "Executed N tests, with 0 failures"（崩溃不等于 failure），
  但 Failing tests 列表里列出每个崩溃的测试方法。

### 根因：`ModelContext` 不持有 `ModelContainer`

`ModelContext` 是轻量引用，不保活 `ModelContainer`。如果调用方只持有 context（或
持有从 context 构造的 Repository）而让 container 逃逸出作用域被释放，**后续任何
save / fetch 都会触发 SwiftData 内部 SIGTRAP**（悬垂引用，框架用断言保护）。

本项目已在 `MiLens/Persistence/RepositoryEnvironment.swift` 的 `FallbackContainer`
注释里记录过同样教训，但**测试代码重复犯了**。

### 判别方法（二分定位）

写一组最小诊断测试，对比以下维度：

| 维度 | 崩 | 不崩 |
|------|----|------|
| 裸 `context.save()`（不经 Repository） | 否 | — |
| `let (repo, _) = makeRepo()` 后 repo 操作 | **是** | — |
| `let (repo, container) = makeRepo()` 后操作 | — | 否 |

只要"丢弃 container"这一列崩、"保活 container"这一列不崩，就是本症。

### 修复模式

在测试类里用数组把 container 持有到测试类生命周期结束：

```swift
final class PhotoRepositoryTests: XCTestCase {
    /// 保活已创建的容器：ModelContext 不持有 ModelContainer，
    /// 调用方若只取 repo 而丢弃 container（如 `let (repo, _)`），
    /// save/fetch 会触发 SwiftData 内部 SIGTRAP。
    private var keepAlive: [ModelContainer] = []

    private func makeRepo() -> (SwiftDataPhotoRepository, ModelContainer) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        keepAlive.append(container)   // ← 关键
        let repo = SwiftDataPhotoRepository(context: container.mainContext)
        return (repo, container)
    }
}
```

调用方代码（`let (repo, _) = makeRepo()`）**无需改动**——保活在工厂内部完成。

### 生产代码同样适用

`FallbackContainer.shared` 就是这个模式：用 `static let` 缓存，避免
`EnvironmentKey.defaultValue` 每次新建容器并在返回后释放。

---

## 崩溃 2：`deallocated with non-zero retain count`

### 症状

`@Observable` 类实例释放时进程崩溃，日志提到 retain count。

### 根因：`deinit` 中创建 `Task` 隐式捕获 `self`

```swift
@MainActor @Observable
final class Foo {
    deinit {
        // ❌ registry 解析为 self.registry → 隐式捕获 self
        //    Task 强引用 deallocating 实例 → 悬垂崩溃
        Task { await registry.cancel(id) }
    }
}
```

`@Observable` 宏不允许 `nonisolated` 可变存储属性，所以 deinit（非隔离）
常常需要访问实例属性，一不小心就隐式捕获 self。

### 修复模式：先取局部变量再建 Task

```swift
nonisolated(unsafe) private let registry: ListenerRegistry

deinit {
    // ✅ 先取出实例属性到局部变量，闭包只捕获局部值
    let id = ObjectIdentifier(self)
    let registry = self.registry
    Task { await registry.cancel(id) }
}
```

---

## 陷阱：`@Attribute(.unique)` 冲突是 upsert，不抛错

### 症状

测试期望"插入相同 originalURI 抛错 + 回滚 + 后续可继续"，但实际：
- 冲突插入**不抛错**
- 旧记录被**静默覆盖**（数据完整性破坏！）

### 根因

SwiftData 的 `@Attribute(.unique)` 冲突语义是 **upsert（覆盖）**，
不是抛错。`context.insert` + `context.save` 在冲突时静默替换旧行。

### 验证（诊断测试）

```swift
try repo.insertPhoto(Photo(uri: "first", originalURI: "dup"))
try repo.insertPhoto(Photo(uri: "conflict", originalURI: "dup"))  // 不抛错！
// 结果：count == 1，uri == "conflict"，旧记录被覆盖
```

### 修复模式：Repository 显式防御

唯一入库路径（`insertPhoto` / `insertPhotos`）在 insert 前按 originalURI 查重，
冲突抛 `PhotoRepositoryError.duplicateOriginalURI`，批量 insert 发现冲突整批 rollback：

```swift
func insertPhoto(_ photo: Photo) throws {
    if try photoExists(originalURI: photo.originalURI) {
        throw PhotoRepositoryError.duplicateOriginalURI(photo.originalURI)
    }
    context.insert(photo)
    try context.saveOrRollback()
}

private func photoExists(originalURI: String) throws -> Bool {
    let d = FetchDescriptor<Photo>(predicate: #Predicate { $0.originalURI == originalURI })
    return try context.fetchCount(d) > 0
}
```

### 调用方约定

- 扫描/导入（`ImportService` / `ScanService`）已在调用前用 `getAllOriginalURIs()` 查重；
- `insertPhoto` 的显式检查是**最后一道防线**，防止竞态/漏洞下静默覆盖。

---

## 测试侧陷阱：磁盘容器 + `defer removeItem`

### 症状

```
BUG IN CLIENT OF libsqlite3.dylib: database integrity compromised by API violation:
vnode unlinked while in use: .../test.sqlite-wal
```

### 根因

container 被 `keepAlive` 保活后仍持有 sqlite 文件句柄，
`defer { try? FileManager.default.removeItem(at: dir) }` 在测试方法返回时
立即删文件 → 句柄失效。

### 修复

磁盘测试目录改用模拟器 tmp（UUID 命名，系统自动清理），
**不在测试内手动删除**：

```swift
private func makeDiskRepo() throws -> (..., URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PhotoRepositoryTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // ... 不 defer removeItem，由模拟器 tmp 自动清理
}
```

---

## 快速自查清单

遇到 SwiftData 崩溃时按此顺序排查：

1. **是不是既有问题？**（stash 改动重跑，崩溃集合不变 → 既有）
2. **container 是否被保活？**（找 `let (repo, _)` 这类丢弃写法）
3. **是不是 deinit 里建 Task？**（搜 `deinit {` + `Task {`）
4. **是不是 unique 冲突被当成抛错用了？**（冲突是 upsert）
5. **是不是磁盘测试 `defer removeItem` 撞上了保活的 container？**

---

## 相关代码位置

- `MiLens/Persistence/RepositoryEnvironment.swift` — `FallbackContainer.shared`（生产保活）
- `MiLens/Persistence/PhotoRepository.swift` — `insertPhoto` 显式防重
- `MiLensTests/PetRepositoryTests.swift` / `PhotoRepositoryTests.swift` — `keepAlive` 模式
- `MiLens/Services/Store/ProEntitlementStore.swift` — deinit 局部变量修复
