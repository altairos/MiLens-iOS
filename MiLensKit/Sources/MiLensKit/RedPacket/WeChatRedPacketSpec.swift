//  WeChatRedPacketSpec —— 微信红包封面开放平台规格常量（创作 Tab 新增项目）。
//
//  微信红包封面有严格平台规格（尺寸/格式/大小），App 导出的素材必须满足才能
//  上传到微信红包封面开放平台。规格来源：微信红包封面开放平台《制作规范》。
//
//  App 只负责生成符合规格的素材 + 场景模拟预览，不介入发布流程
//  （发布需用户自行登录 cover.weixin.qq.com，有注册门槛+审核+付费）。
//  DESIGN.md §4：纯数据常量，无 IO / 无 SwiftUI 依赖。

import Foundation

/// 微信红包封面开放平台素材规格（来源：官方《制作规范》）。
public enum WeChatRedPacketSpec {

    // MARK: - 封面图（封面样式）

    /// 封面图尺寸（像素，宽×高）。
    public static let coverImageWidth = 957
    public static let coverImageHeight = 1278

    /// 封面图最大文件大小（字节，≤500KB）。
    public static let coverImageMaxBytes = 500 * 1024

    // MARK: - 封面故事图

    /// 封面故事图尺寸（像素，宽×高）。
    public static let storyImageWidth = 750
    public static let storyImageHeight = 1250

    /// 封面故事图最大文件大小（字节，≤300KB）。
    public static let storyImageMaxBytes = 300 * 1024

    // MARK: - 品牌 logo

    /// 品牌 logo 最大尺寸（像素，宽×高均 ≤200）。
    public static let logoMaxWidth = 200
    public static let logoMaxHeight = 200

    /// 品牌 logo 最大文件大小（字节，≤100KB）。
    public static let logoMaxBytes = 100 * 1024

    // MARK: - 文案约束

    /// 封面简称最大字数（微信硬约束：最多展示 8 个字）。
    public static let coverTitleMaxLength = 8

    // MARK: - 格式

    /// 支持的图片格式。
    public static let validImageFormats = ["png", "jpg", "jpeg"]

    // MARK: - 安全区（拆红包页关键元素避让）

    /// 拆红包页金额数字与「開」按钮遮挡区占封面图高度比例（从底部起）。
    /// 封面排版需把宠物名/关键视觉放在此线之上的安全区。
    public static let safeZoneTopRatio = 0.55
}
