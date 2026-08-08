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

    /// 订阅任务注册表：@Observable 宏不允许 nonisolated 可变存储属性，deinit（非隔离）
    /// 无法直接访问实例任务句柄；改用非隔离静态注册表按实例 ID 取消（Task 是 Sendable）。
    private static nonisolated(unsafe) var activeUpdates: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(store: any StoreService) {
        self.store = store
        let id = ObjectIdentifier(self)
        let task = Task { [weak self] in
            guard let self else { return }
            for await status in store.proStatusUpdates {
                guard !Task.isCancelled else { return }
                self.status = status
            }
        }
        Self.activeUpdates[id] = task
    }

    deinit {
        let id = ObjectIdentifier(self)
        Self.activeUpdates[id]?.cancel()
        Self.activeUpdates[id] = nil
    }

    /// 显式校准一次权益（购买/恢复成功、根视图启动与页面出现时调用）。
    /// 冷启动必须由 RootTabView 首次出现触发：Transaction.updates 不保证推送当前权益，
    /// 否则已购用户首次进入创作门控前状态仍是初始 .inactive。
    func refresh() async {
        status = await store.currentProStatus()
    }
}
