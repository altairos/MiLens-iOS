//  RedPacketCoverLogic —— 微信红包封面纯决策逻辑（创作 Tab 新增项目）。
//
//  负责封面简称截断、规格校验、上传引导文案组装。
//  View 层（RedPacketCoverView）负责渲染与导出；宿主负责 IO。
//
//  边界：App 只生成符合微信平台规格的素材 + 场景模拟预览，不介入发布流程。
//  发布需用户自行登录 cover.weixin.qq.com（有注册门槛 + 审核 + 付费）。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

/// 封面图校验结果。
public enum RedPacketCoverValidationResult: Equatable, Sendable {
    case valid
    case invalidSize(expected: (width: Int, height: Int), actual: (width: Int, height: Int))
    case invalidFileSize(maxBytes: Int, actualBytes: Int)
    case invalidFormat

    public static func == (lhs: RedPacketCoverValidationResult, rhs: RedPacketCoverValidationResult) -> Bool {
        switch (lhs, rhs) {
        case (.valid, .valid):
            return true
        case (.invalidFormat, .invalidFormat):
            return true
        case (.invalidSize(let l, let r), .invalidSize(let l2, let r2)):
            return l.width == l2.width && l.height == l2.height && r.width == r2.width && r.height == r2.height
        case (.invalidFileSize(let m1, let a1), .invalidFileSize(let m2, let a2)):
            return m1 == m2 && a1 == a2
        default:
            return false
        }
    }
}

/// 红包封面用的宠物投影（脱离 SwiftData @Model）。
public struct RedPacketPetInput: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let avatarPath: String

    public init(id: UUID = UUID(), name: String = "", avatarPath: String = "") {
        self.id = id
        self.name = name
        self.avatarPath = avatarPath
    }
}

public enum RedPacketCoverLogic {

    // MARK: - 封面简称

    /// 生成封面简称：取宠物名，截断到微信硬约束的 8 字以内。
    /// 空名回退到通用文案。
    public static func coverTitle(petName: String) -> String {
        if petName.isEmpty { return "我的红包封面" }
        return truncate(petName, max: WeChatRedPacketSpec.coverTitleMaxLength)
    }

    // MARK: - 规格校验

    /// 校验封面图数据是否满足微信平台规格。
    public static func validateCoverImage(
        data: Data, width: Int, height: Int, fileExtension: String
    ) -> RedPacketCoverValidationResult {
        // 格式
        let ext = fileExtension.lowercased()
        guard WeChatRedPacketSpec.validImageFormats.contains(ext) else {
            return .invalidFormat
        }
        // 尺寸
        let expectedW = WeChatRedPacketSpec.coverImageWidth
        let expectedH = WeChatRedPacketSpec.coverImageHeight
        if width != expectedW || height != expectedH {
            return .invalidSize(
                expected: (expectedW, expectedH),
                actual: (width, height)
            )
        }
        // 文件大小
        if data.count > WeChatRedPacketSpec.coverImageMaxBytes {
            return .invalidFileSize(
                maxBytes: WeChatRedPacketSpec.coverImageMaxBytes,
                actualBytes: data.count
            )
        }
        return .valid
    }

    /// 校验封面故事图数据是否满足规格。
    public static func validateStoryImage(
        data: Data, width: Int, height: Int
    ) -> RedPacketCoverValidationResult {
        let expectedW = WeChatRedPacketSpec.storyImageWidth
        let expectedH = WeChatRedPacketSpec.storyImageHeight
        if width != expectedW || height != expectedH {
            return .invalidSize(
                expected: (expectedW, expectedH),
                actual: (width, height)
            )
        }
        if data.count > WeChatRedPacketSpec.storyImageMaxBytes {
            return .invalidFileSize(
                maxBytes: WeChatRedPacketSpec.storyImageMaxBytes,
                actualBytes: data.count
            )
        }
        return .valid
    }

    // MARK: - 上传引导文案

    /// 上传引导步骤（本地化 key，App 层 Localizable.xcstrings 对应条目）。
    public static func uploadGuideSteps() -> [String] {
        [
            "redpacket.guide.step1", // 1. 登录微信红包封面开放平台 cover.weixin.qq.com
            "redpacket.guide.step2", // 2. 点击「定制封面」，上传导出的封面图
            "redpacket.guide.step3", // 3. 填写封面简称、上传品牌 logo（可选）
            "redpacket.guide.step4", // 4. 提交审核（约 1-2 小时）
            "redpacket.guide.step5", // 5. 审核通过后选择使用人数并支付，生成领取链接
        ]
    }

    /// 平台注册门槛提示文案 key。
    public static func eligibilityNoticeKey() -> String {
        "redpacket.guide.eligibility" // 需视频号/公众号粉丝≥100 或企业认证
    }

    /// 导出文件名（含宠物名，微信规范无强制文件名要求，用语义化命名）。
    public static func exportFilename(petName: String) -> String {
        let safe = petName.isEmpty ? "pet" : petName
        return "redpacket_cover_\(safe).png"
    }

    // MARK: - 内部工具

    /// 按字符数截断（不按 UTF-16 单元，避免 emoji 误切）。
    private static func truncate(_ string: String, max length: Int) -> String {
        guard string.count > length else { return string }
        return String(string.prefix(length))
    }
}
