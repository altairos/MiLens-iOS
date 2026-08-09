//  ProEntitlementStore —— 应用级 Pro 权益状态（@Observable，组合根注入）。
//
//  P2 修复（权益流广播语义）：StoreService.proStatusUpdates 是单消费者 AsyncStream，
//  设置页/付费墙若直接并发消费会竞争元素、不保证双方都收到同一次更新。
//  本 store 作为**唯一**流消费者，把权益收口为应用级可观察状态；
//  页面与 ViewModel 一律读 status/isPro，不再直接消费流。
//
//  职责：
//  - 订阅 store.proStatusUpdates（Transaction.updates / 购买 / 恢复驱动），更新 status；
//  - refresh()：显式查询 currentProStatus（购买/恢复成功、页面出现时的即时校准）。
//
//  DESIGN.md §4：Service 编排 IO；本 store 是权益状态的单一事实源。

import Foundation
import Observation

@MainActor
@Observable
final class ProEntitlementStore {

    private(set) var status: ProStatus = .inactive

    /// 是否已解锁 Pro（付费墙/功能门控统一判定）。
    var isPro: Bool { status.isActive }

    private let store: any StoreService

    /// 订阅任务注册表（actor 隔离）：@Observable 宏不允许 nonisolated 可变存储属性，
    /// deinit（非隔离）无法直接访问实例任务句柄；注册表按令牌管理任务生命周期。
    /// actor 隔离消除 init（MainActor）与 deinit（任意线程）对静态字典的数据竞争。
    ///
    /// 令牌用 UUID 而非 ObjectIdentifier：对象回收后内存地址可能复用，导致前序实例
    /// 的残留墓碑误杀后序新实例（评审阻塞项）。UUID 全局唯一，旧令牌永不被新实例复用。
    ///
    /// 取消墓碑（cancelledIDs）：仅在「cancel 先于 register 到达」竞态时创建——
    /// 即 cancel 时 tasks 中找不到该令牌，说明 init 的 register Task 尚未到达 actor。
    /// 墓碑由随后到达的 register 消费并移除。正常路径（cancel 在 register 之后）不创建墓碑，
    /// 避免对象释放后墓碑长期残留。
    /// nonisolated(unsafe)：init 赋值后只读，deinit（非隔离）需要访问实例注册表；
    /// 测试注入独立实例，避免与宿主 App/并行测试类共享 .shared 的计数相互干扰。
    actor ListenerRegistry {
        private var tasks: [UUID: Task<Void, Never>] = [:]
        private var cancelledIDs: Set<UUID> = []

        func register(_ id: UUID, _ task: Task<Void, Never>) {
            if cancelledIDs.remove(id) != nil {
                // 取消墓碑：cancel 先于 register 到达 → 新注册立即取消，墓碑随之消费
                task.cancel()
                return
            }
            tasks[id] = task
        }

        func cancel(_ id: UUID) {
            if let task = tasks.removeValue(forKey: id) {
                // 正常路径：任务已注册，直接取消，无需墓碑。
                task.cancel()
            } else {
                // cancel 先于 register 到达（竞态）：创建一次性墓碑，
                // 待 register 消费；register 必然到达（由 init 提交）。
                cancelledIDs.insert(id)
            }
        }

        /// 当前注册任务数（测试断言注册表无残留）。
        var activeCount: Int { tasks.count }
    }

    /// 生产默认注册表（测试注入独立实例，见 ProEntitlementStoreTests）。
    static let shared = ListenerRegistry()

    /// 实例注册表：init 注入后只读；deinit 经 nonisolated(unsafe) 访问提交取消任务。
    nonisolated(unsafe) private let registry: ListenerRegistry
    /// 实例监听令牌（UUID 全局唯一，不会因对象回收复用而误杀新实例）。
    private let listenerToken = UUID()

    init(store: any StoreService, registry: ListenerRegistry = ProEntitlementStore.shared) {
        self.store = store
        self.registry = registry
        let id = listenerToken
        let task = Task { [weak self] in
            // 每次迭代才短暂持有 self：任务不长期强引用实例，
            // 实例释放后下一轮迭代 guard 失败退出——无「静态字典 → Task → self」保活环。
            defer { Task { await registry.cancel(id) } }
            for await status in store.proStatusUpdates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.status = status
            }
        }
        Task { await registry.register(id, task) }
    }

    deinit {
        // 先取出注册表再提交 Task：闭包只捕获局部值，避免隐式捕获 self
        // （Task 强引用 deallocating 实例会悬垂崩溃）。
        let id = listenerToken
        let registry = self.registry
        Task { await registry.cancel(id) }
    }

    /// 显式校准一次权益（购买/恢复成功、根视图启动与页面出现时调用）。
    /// 冷启动必须由 RootTabView 首次出现触发：Transaction.updates 不保证推送当前权益，
    /// 否则已购用户首次进入创作门控前状态仍是初始 .inactive。
    func refresh() async {
        status = await store.currentProStatus()
    }
}
