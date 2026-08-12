//  ShareComponents —— 系统分享通用组件（ShareItem + ShareSheet）。
//  被创作类页面共用：BeadPatternResult / BusinessCard / GrowthCompare / PetCard / SharePreviewSheet。
//  从 BeadPatternResultView 提取为共享组件（规模守卫 + 消除跨文件隐式依赖）。

import SwiftUI
import UIKit

/// 系统分享的数据项（唯一 URL，驱动 sheet/item）。
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIActivityViewController 的 SwiftUI 包装（系统分享面板，完全由用户掌控，不联网）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
