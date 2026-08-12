//  Schema 版本与迁移计划（DESIGN.md §7）。
//
//  ⚠️ 版本纪律：V1 已冻结（2026-08），V2 追加字段（PetEvent.body/sourceType/isPinned/relatedPhotoID）。
//  后续任何字段/关系变更必须：定义 SchemaV3（版本号 3.x）+ 追加 MigrationStage；
//  绝不允许改动已冻结版本的定义后保持版本号不变（会导致存量库打开失败）。
//
//  迁移策略（正式决策，2026-08）：
//  - 产品尚未发布，V1.0 首发前清除所有旧开发数据库（删除 App 重装）——
//    这是正式的首发策略，不是临时规避。理由：SwiftData 对「新增唯一约束」
//    不支持 lightweight migration；P0 修复前创建的开发库（无 originalURI unique）
//    与 V1 模型不兼容，custom migration 无法可靠重建其内部 unique index。
//  - V1 → V2：纯新增可空/有默认值字段，SwiftData lightweight migration 自动处理。
//  - 首发后任何 schema 变更：递增 SchemaV3（版本号 3.x）并追加 MigrationStage。
//  - 测试一律使用 in-memory 容器，不依赖迁移路径。

import Foundation
import SwiftData

/// Schema V1 —— MiLens 初始数据模型（Pet / Photo / PetEvent，含 originalURI 唯一约束）。
/// 已冻结，勿改定义。
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Pet.self, Photo.self, PetEvent.self]
    }
}

/// Schema V2 —— 扩展 PetEvent（body/sourceType/isPinned/relatedPhotoID）。
/// 纯新增可空字段，lightweight migration 自动处理。
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Pet.self, Photo.self, PetEvent.self]
    }
}

/// 迁移计划——V1 → V2（lightweight），后续版本按序追加 stage。
enum MiLensMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        // V1 → V2：纯新增字段（有默认值），SwiftData 自动 lightweight migration。
        [MigrationStage.lightweight(from: SchemaV1.self, to: SchemaV2.self)]
    }
}
