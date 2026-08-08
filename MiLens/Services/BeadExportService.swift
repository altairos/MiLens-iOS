//  BeadExportService —— 拼豆图纸导出服务（A4 PNG 渲染 / 保存相册 / 分享缓存文件）。
//  对应源端 BeadPatternPage.exportPattern / sharePattern 的 IO 部分；
//  像素渲染由 MiLensKit renderA4Export + getA4Size 完成（视觉结果与源端 parity）。
//  字节序差异：源端鸿蒙 PixelMap RGBA_8888 需要 swapRedBlueChannelsInPlace，
//  iOS 用 CGImage byteOrder32Big 直接解释 RGBA buffer，无需交换通道。

import UIKit
import Photos
import MiLensKit

struct BeadExportService {

    /// 渲染 A4 高清图纸为 PNG Data（对应源端 exportPattern 的 renderA4Export → PNG 编码）。
    /// - Parameters:
    ///   - photoPixels: 原图 RGBA 缩略像素（源端 loadPhotoPixels，最大边 560），可空。
    func renderA4PNG(pattern: BeadPattern,
                     photoPixels: [UInt8]?, photoW: Int, photoH: Int,
                     exportOpts: BeadExportOpts?) -> Data? {
        let buffer = renderA4Export(pattern: pattern, photoPixels: photoPixels,
                                    photoW: photoW, photoH: photoH, exportOpts: exportOpts)
        let a4 = getA4Size()
        guard let cgImage = makeCGImage(rgba: buffer, width: a4.width, height: a4.height) else {
            return nil
        }
        return UIImage(cgImage: cgImage).pngData()
    }

    /// 保存 PNG 到系统相册（对应源端 createAsset + writePixelMapAsPng）。
    /// 需要 NSPhotoLibraryAddUsageDescription（已配置）。
    func saveToPhotoLibrary(pngData: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: pngData, options: nil)
        }
    }

    /// 写入分享缓存文件（对应源端 sharePattern 写入 cacheDir/bead_pattern_share.png）。
    func writeShareCache(pngData: Data, filename: String = "bead_pattern_share.png") throws -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent(filename)
        try pngData.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 像素 → UIImage / CGImage

    /// 将 RGBA 像素数组包装为 UIImage（结果画布预览共用）。
    static func makeImage(rgba: [UInt8], width: Int, height: Int) -> UIImage? {
        guard let cgImage = makeCGImage(rgba: rgba, width: width, height: height) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// 将 RGBA 像素数组包装为 CGImage（premultipliedLast + byteOrder32Big）。
    /// A4 导出 buffer 全像素 alpha=255，预乘语义下与直通值等价。
    private static func makeCGImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              rgba.count >= width * height * 4 else { return nil }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    }
}
