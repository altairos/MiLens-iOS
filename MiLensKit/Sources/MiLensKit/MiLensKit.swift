import Foundation

/// MiLensKit 公共入口占位。
///
/// 拼豆算法（生成管线/色板/色彩空间/评分/渲染导出）、诊断（错误分类/任务日志）
/// 与共享类型将按 `DESIGN.md` §8 与 `MIGRATION_ASSESSMENT.md` §3 从源端 `shared` HSP
/// 逐模块翻译迁入。导出面用 `public` 控制，对应源端 `shared/Index.ets`。
public enum MiLensKit {
    /// 当前包版本，迁移期用于验证依赖链连通。
    public static let version = "0.1.0"
}
