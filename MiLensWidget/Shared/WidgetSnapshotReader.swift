//  WidgetSnapshotReader —— Widget Extension 从 App Group 读取共享快照。
//
//  Widget 不直接打开 SwiftData store（WidgetKit-Design.md §6.1）：所有数据经主 App
//  写入 App Group 容器的 JSON 快照 + 降采样缩略图。本结构封装读取与图像加载逻辑。
//
//  注意：图像解码有内存上限（Widget 进程受限），因此只加载 ≤300pt 的缩略图，
//  并使用 ImageIO 的降采样选项避免全尺寸解码。

import Foundation
import UIKit
import ImageIO
import MiLensKit

struct WidgetSnapshotReader {

    /// App Group 容器 URL（只读访问）。
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedConfig.appGroupID)
    }

    /// 读取并解码快照 JSON。读取失败 / 解码失败 / schema 不兼容均返回 nil（展示 stale 状态）。
    static func read() -> WidgetSnapshot? {
        guard let containerURL else { return nil }
        let fileURL = containerURL.appendingPathComponent(WidgetSharedConfig.snapshotFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// 缩略图文件在 App Group 中的完整 URL。
    static func thumbnailURL(_ fileName: String) -> URL? {
        guard let containerURL else { return nil }
        return containerURL
            .appendingPathComponent(WidgetSharedConfig.thumbnailsDirName)
            .appendingPathComponent(fileName)
    }

    /// 加载缩略图并降采样到 Widget 所需尺寸（避免内存超限）。
    ///
    /// - Parameters:
    ///   - fileName: 缩略图文件名（PhotoProjection.thumbnailFileName）
    ///   - maxSize: 最大边长（pt）；默认 300
    /// - Returns: 降采样后的 UIImage；文件缺失或解码失败返回 nil
    static func loadImage(_ fileName: String, maxSize: CGFloat = 300) -> UIImage? {
        guard let fileURL = thumbnailURL(fileName),
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize * UIScreen.main.scale
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
