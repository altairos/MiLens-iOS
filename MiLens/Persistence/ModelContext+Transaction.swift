//  ModelContext+Transaction —— SwiftData 保存事务封装。
//  context.save() 失败不会自动回滚：失败的 insert/update/delete 会残留在
//  pending changes 中，污染同一上下文的后续保存（例如唯一约束冲突后，未回滚
//  的失败对象会让下一次 save 继续失败，导入/编辑链路被卡死）。
//  仓储层统一经 saveOrRollback() 提交——失败即回滚全部 pending changes 并重抛，
//  保证上下文回到调用前的干净状态（评审 P 修复）。

import Foundation
import SwiftData

extension ModelContext {
    /// 保存当前事务；失败时回滚 pending changes 并重抛错误。
    /// 调用方（Repository）保证抛错后内存对象状态与持久层一致。
    func saveOrRollback() throws {
        do {
            try save()
        } catch {
            rollback()
            throw error
        }
    }
}
