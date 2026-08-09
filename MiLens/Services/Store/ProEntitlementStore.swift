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
    /// deinit（非隔离）无法直接访问实例任务句柄；注册表按实例 ID 管理任务生命周期。
    /// actor 隔离消除 init（MainActor）与 deinit（任意线程）对静态字典的数据竞争。
    /// 取消墓碑（cancelledIDs）：cancel 先于 register 到达 actor 时，晚到的注册会被
    /// 立即取消且不写入注册表——消除「已结束任务被重新写入」的残留（评审阻塞项）；
    /// 墓碑由随后到达的 register 消费，不长期增长。
    /// internal：供测试断言乱序/立即释放路径的注册表状态。
    actor ListenerRegistry {
        private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
        private var cancelledIDs: Set<ObjectIdentifier> = []

        func register(_ id: ObjectIdentifier, _ task: Task<Void, Never>) {
            if cancelledIDs.remove(id) != nil {
                // 取消墓碑：deinit/任务结束的清理先于注册到达 → 新注册立即取消，不残留
                task.cancel()
                return
            }
            tasks[id] = task
        }

        func cancel(_ id: ObjectIdentifier) {
            if let task = tasks.removeValue(forKey: id) {
                task.cancel()
            }
            cancelledIDs.insert(id)
        }

        /// 当前注册任务数（测试断言注册表无残留）。
        var activeCount: Int { tasks.count }
    }

    /// internal：ProEntitlementStoreTests 断言注册表生命周期。
    static let registry = ListenerRegistry()

    init(store: any StoreService) {
        self.store = store
        let id = ObjectIdentifier(self)
        let task = Task { [weak self] in
            // 每次迭代才短暂持有 self：任务不长期强引用实例，
            // 实例释放后下一轮迭代 guard 失败退出——无「静态字典 → Task → self」保活环。
            defer { Task { await Self.registry.cancel(id) } }
            for await status in store.proStatusUpdates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.status = status
            }
        }
        Task { await Self.registry.register(id, task) }
    }

    deinit {
        let id = ObjectIdentifier(self)
        Task { await Self.registry.cancel(id) }
    }

    /// 显式校准一次权益（购买/恢复成功、根视图启动与页面出现时调用）。
    /// 冷启动必须由 RootTabView 首次出现触发：Transaction.updates 不保证推送当前权益，
    /// 否则已购用户首次进入创作门控前状态仍是初始 .inactive。
    func refresh() async {
        status = await store.currentProStatus()
    }
}
