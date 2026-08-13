import Foundation

// RedPacketExportLogic — 红包封面导出决策纯逻辑（对应红包封面开发计划 §6.3）。
//
// 导出时封面和预览缩略图共用同一份草稿渲染结果，
// 不让预览图和最终导出图使用两套排版逻辑。
// PNG 不超限时优先使用，超限时按 JPEG 降级链编码。

// MARK: - 导出格式决策

/// 导出编码格式。
public enum RedPacketExportFormat: String, Sendable, Equatable {
    case png
    case jpeg
}

/// 导出编码结果。
public struct RedPacketExportData: Sendable, Equatable {
    /// 编码后的图片数据。
    public var data: Data
    /// 编码格式。
    public var format: RedPacketExportFormat
    /// 文件扩展名。
    public var fileExtension: String

    public init(data: Data, format: RedPacketExportFormat, fileExtension: String) {
        self.data = data
        self.format = format
        self.fileExtension = fileExtension
    }
}

/// 导出编码决策（PNG 优先，超限降级 JPEG）。
/// 对应红包封面开发计划 §6.3：PNG 不超限时优先使用，超限时按 JPEG 降级链编码。
public enum RedPacketExportLogic {

    /// 从一组候选编码数据中选出满足微信规格的最佳结果。
    ///
    /// 候选顺序：PNG → JPEG 0.9 → JPEG 0.6。
    /// 返回首个满足文件大小限制的结果；全部超限则返回最小的 JPEG（允许用户自行处理）。
    public static func chooseBest(
        png: Data?, jpegHigh: Data?, jpegLow: Data?
    ) -> RedPacketExportData? {
        let maxBytes = WeChatRedPacketSpec.coverImageMaxBytes

        // 1. PNG ≤ 限 → 首选
        if let png, png.count <= maxBytes {
            return RedPacketExportData(data: png, format: .png, fileExtension: "png")
        }

        // 2. JPEG 0.9 ≤ 限
        if let jpg = jpegHigh, jpg.count <= maxBytes {
            return RedPacketExportData(data: jpg, format: .jpeg, fileExtension: "jpg")
        }

        // 3. JPEG 0.6 ≤ 限
        if let jpg = jpegLow, jpg.count <= maxBytes {
            return RedPacketExportData(data: jpg, format: .jpeg, fileExtension: "jpg")
        }

        // 4. 全部超限 → 返回最小的（JPEG 0.6 优先）
        if let jpegLow {
            return RedPacketExportData(data: jpegLow, format: .jpeg, fileExtension: "jpg")
        }
        if let jpegHigh {
            return RedPacketExportData(data: jpegHigh, format: .jpeg, fileExtension: "jpg")
        }
        if let png {
            return RedPacketExportData(data: png, format: .png, fileExtension: "png")
        }
        return nil
    }

    /// 判断文件大小是否满足微信规格。
    public static func isWithinSizeLimit(_ data: Data) -> Bool {
        data.count <= WeChatRedPacketSpec.coverImageMaxBytes
    }

    /// 聊天预览缩略图规格（封面在红包卡片中的缩略图比例）。
    public static func chatThumbnailSpec() -> (width: Int, height: Int) {
        // 红包卡片缩略图大致比例（与封面同比例，缩小尺寸）
        let thumbWidth = 200
        let ratio = Double(WeChatRedPacketSpec.coverImageHeight) /
                    Double(WeChatRedPacketSpec.coverImageWidth)
        let thumbHeight = Int(Double(thumbWidth) * ratio)
        return (thumbWidth, thumbHeight)
    }

    /// 导出文件名（含宠物名）。
    public static func exportFilename(
        petName: String, fileExtension: String = "png"
    ) -> String {
        RedPacketCoverLogic.exportFilename(petName: petName)
            .replacingOccurrences(of: ".png", with: ".\(fileExtension)")
    }
}
