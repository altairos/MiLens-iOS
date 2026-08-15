//  RedPacketCoverEncodeLogic —— 红包封面导出编码链纯决策逻辑。
//  从 RedPacketUploadGuideView 下沉（audit-6 P1-4：0% 覆盖大文件补测）。
//  编码器以闭包注入（真实调用传 UIImage.pngData/jpegData），使字节预算决策链可脱离 UIKit 单测。
//  纯决策逻辑，无 IO/无 SwiftUI 依赖（DESIGN.md §4）。

import Foundation
import MiLensKit

/// 微信红包封面导出编码决策（对照源端保存/分享双链路字节预算）。
enum RedPacketCoverEncodeLogic {

    /// 保存链：PNG ≤ 上限 → JPEG(0.9) ≤ 上限 → JPEG(0.6) 兜底；
    /// 三级编码全部失败才返回 nil（调用方提示 create.encode.failed）。
    static func encodeForSave(
        pngData: () -> Data?,
        jpegData: (Double) -> Data?,
        maxBytes: Int = WeChatRedPacketSpec.coverImageMaxBytes
    ) -> Data? {
        if let png = pngData(), png.count <= maxBytes {
            return png
        }
        if let jpg = jpegData(0.9), jpg.count <= maxBytes {
            return jpg
        }
        return jpegData(0.6)
    }

    /// 分享链：PNG ≤ 上限 → JPEG(0.85)；JPEG 失败回退空 Data
    /// （沿用源端语义：分享缓存写入不因编码失败中断）。
    static func encodeForShare(
        pngData: () -> Data?,
        jpegData: (Double) -> Data?,
        maxBytes: Int = WeChatRedPacketSpec.coverImageMaxBytes
    ) -> Data {
        if let png = pngData(), png.count <= maxBytes {
            return png
        }
        return jpegData(0.85) ?? Data()
    }
}
