//  组合根（DESIGN.md §4.1）。
//  应用级依赖（ModelContainer / Repository）在此构造并注入。
//  对应源端 EntryAbility（HarmonyOS UIAbility 生命周期入口）+ AppServiceLocator DI。

import SwiftUI
import SwiftData

@main
struct MiLensApp: App {
    private let container: ModelContainer
    private let petRepo: any PetRepositoryProtocol
    private let photoRepo: any PhotoRepositoryProtocol

    init() {
        // V1.0 干净 schema——迁移计划为空。创建失败无恢复意义（无数据库 app 不可用）。
        // 测试环境（XCTest host 加载 @main App）切 in-memory，避免模拟器
        // Application Support 目录不可写导致 CoreData 存储错误噪音。
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = isTesting
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration()
        let container = try! ModelContainer(
            for: schema,
            migrationPlan: MiLensMigrationPlan.self,
            configurations: [config]
        )
        self.container = container
        self.petRepo = SwiftDataPetRepository(context: container.mainContext)
        self.photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .modelContainer(container)
                .environment(\.petRepository, petRepo)
                .environment(\.photoRepository, photoRepo)
        }
    }
}
