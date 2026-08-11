import Foundation
import MiLensKit
import os

// DecorationCatalogLoader — 装饰资源目录 Bundle 加载器。
//
// catalog.json 由 tools/frame_import.py 从素材 manifest（每相框一份 frame.json）
// 合并生成，位于 `MiLens/Resources/Decorations/catalog.json`，随 App 打包。
// App 启动后由 ViewModelFactory 调用本加载器构造 DecorationCatalog 注入编辑器 ViewModel。
//
// 容错策略：文件缺失 / JSON 解析失败时返回空目录（V1.0 默认无装饰素材），
// 不抛错、不阻塞编辑器；问题记录到日志便于诊断。

enum DecorationCatalogLoader {
    /// catalog.json 在 Bundle 内的位置（同时兼容扁平打包与保留 Decorations/ 子目录两种情况）。
    static func load() -> DecorationCatalog {
        let log = Logger(subsystem: "com.milens.app", category: "DecorationCatalog")
        let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "Decorations")
            ?? Bundle.main.url(forResource: "catalog", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else {
            // V1.0 默认无素材：返回空目录，编辑器仍可正常工作（仅无装饰面板内容）。
            return .empty
        }
        do {
            return try JSONDecoder().decode(DecorationCatalog.self, from: data)
        } catch {
            log.error("load: catalog.json 解析失败（\(error.localizedDescription)），回退空目录")
            return .empty
        }
    }
}
