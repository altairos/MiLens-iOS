//  WidgetDeepLink —— Widget 深链 URL → 类型安全 Route 映射。
//
//  WidgetKit-Design.md §6.3：深链建议 milens://photo/{id}、milens://pet/{id}、
//  milens://timeline?pet={id}、milens://bead/{id}、milens://anniversary/{petID}?day={dayID}。
//  主 App 统一解析 URL 并映射到类型安全 Route；无效、已删除或迁移后的 ID 回退到
//  对应一级页面，不 crash。
//
//  纯逻辑：URL 解析 → Route 枚举，无 IO / 无 SwiftUI 依赖。可单测。

import Foundation
import MiLensKit

enum WidgetDeepLink {
    /// 把 milens:// 深链 URL 解析为 Route。
    ///
    /// 支持的路径：
    /// - `milens://photo/{uuid}` → `.photoView`
    /// - `milens://pet/{uuid}` → `.petProfile`
    /// - `milens://timeline` → `.timeline`
    /// - `milens://bead/{uuid}` → `.beadPattern`
    /// - `milens://anniversary/{petUUID}?day={dayID}` → `.petProfile`（dayID 预留扩展）
    /// - `milens://home` → nil（回退首页，无需导航）
    ///
    /// - Parameter url: Widget widgetURL 传入的 URL
    /// - Returns: 对应的 Route；无法解析或 UUID 无效时返回 nil（调用方停留在首页）
    static func route(from url: URL) -> Route? {
        guard url.scheme == WidgetSharedConfig.deepLinkScheme else { return nil }

        // host表示路由域（photo / pet / timeline / bead / anniversary / home）
        guard let host = url.host else { return nil }

        switch host {
        case "photo":
            guard let id = uuidFromPath(url) else { return nil }
            return .photoView(photoID: id)
        case "pet":
            guard let id = uuidFromPath(url) else { return nil }
            return .petProfile(petID: id)
        case "timeline":
            return .timeline
        case "bead":
            guard let id = uuidFromPath(url) else { return nil }
            return .beadPattern(photoID: id)
        case "anniversary":
            // 纪念日深链：定位到该纪念日所属伙伴的档案页（与 pet 同为 petProfile）。
            // `day` query 参数当前不消费，预留给未来定位到具体事件区块。
            guard let id = uuidFromPath(url) else { return nil }
            return .petProfile(petID: id)
        case "home":
            // 回首页：调用方切 Tab 即可，无需 push Route
            return nil
        default:
            return nil
        }
    }

    /// 从 URL path 解析 UUID（`milens://photo/XXXX-XXXX/...` → 第一个路径段）。
    private static func uuidFromPath(_ url: URL) -> UUID? {
        let path = url.path
        // path 可能带前导 /，去掉后取第一段
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let firstSegment = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
        return UUID(uuidString: firstSegment)
    }
}
