//  AppTab —— 底部主导航标签（DESIGN.md §1，iOS V1.0 设计稿「首页 | 宠物 | 创作 | 我的」）。
//  对应源端 MainPage 的 Tab 顺序（源端为「相册/伙伴/时间线/更多」，iOS 版重新设计）。

import Foundation

enum AppTab: Int, CaseIterable, Hashable {
    case home
    case pets
    case create
    case settings

    var title: String {
        switch self {
        case .home: return NSLocalizedString("tab.home", comment: "底部标签：首页")
        case .pets: return NSLocalizedString("tab.pets", comment: "底部标签：宠物")
        case .create: return NSLocalizedString("tab.create", comment: "底部标签：创作")
        case .settings: return NSLocalizedString("tab.settings", comment: "底部标签：我的")
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .pets: return "pawprint"
        case .create: return "square.and.pencil"
        case .settings: return "person"
        }
    }
}
