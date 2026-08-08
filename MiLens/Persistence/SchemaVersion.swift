//  Schema 版本与迁移计划（DESIGN.md §7）。
//  V1 即首发基线——模型含 Photo.originalURI 唯一约束（扫描/导入去重主键）。
//
//  ⚠️ V1 已冻结（2026-08）：当前模型（Pet / Photo / PetEvent，含质量字段）
//  即首发 schema。后续任何字段/关系变更必须：定义 SchemaV2（版本号 2.x）
//  + 追加 MigrationStage；绝不允许改动 V1 模型定义后保持版本号不变
//  （会导致存量库打开失败）。
//
//  迁移策略（正式决策，2026-08）：
//  - 产品尚未发布，V1.0 首发前清除所有旧开发数据库（删除 App 重装）——
//    这是正式的首发策略，不是临时规避。理由：SwiftData 对「新增唯一约束」
//    不支持 lightweight migration；P0 修复前创建的开发库（无 originalURI unique）
//    与 V1 模型不兼容，custom migration 无法可靠重建其内部 unique index。
//  - 首发后任何 schema 变更：递增 SchemaV2（版本号 2.x）并追加 MigrationStage。
//  - 测试一律使用 in-memory 容器（Schema(versionedSchema: SchemaV1.self)），
//    不依赖迁移路径。

import Foundation
import SwiftData

/// Schema V1 —— MiLens 首发数据模型（Pet / Photo / PetEvent，含 originalURI 唯一约束）。
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Pet.self, Photo.self, PetEvent.self]
    }
}

/// 迁移计划——V1 起步，无历史阶段（V1 已冻结；旧开发库在首发前清库，见文件头策略）。
enum MiLensMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}
