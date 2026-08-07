//  Schema 版本与迁移计划（DESIGN.md §7）。
//  V1.0 从干净 schema 起步——不复刻源端 16 版历史迁移，迁移阶段为空。
//  后续 schema 变更时：递增 SchemaV2 + 追加 MigrationStage。

import Foundation
import SwiftData

/// Schema V1 —— MiLens 首版数据模型（Pet / Photo / PetEvent）。
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Pet.self, Photo.self, PetEvent.self]
    }
}

/// 迁移计划——V1 起步，无历史阶段。
enum MiLensMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}
