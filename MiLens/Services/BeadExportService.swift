//  BeadExportService —— 拼豆图纸导出服务（A4 PNG 渲染 / 保存相册 / 分享缓存文件）。
//  对应源端 BeadPatternPage.exportPattern / sharePattern 的 IO 部分；
//  像素渲染由 MiLensKit renderA4Export + getA4Size 完成（视觉结果与源端 parity）。
//  字节序差异：源端鸿蒙 PixelMap RGBA_8888 需要 swapRedBlueChannelsInPlace，
//  iOS 用 CGImage byteOrder32Big 直接解释 RGBA buffer，无需交换通道。

import UIKit
import MiLensKit

struct BeadExportService {

    /// 照片库写入经 PhotoLibraryAccess 协议抽象（P2-1 / ADR-0011 §2.2 豁免移除条件）。
    /// 默认真实实现；测试注入 MockPhotoLibraryAccess 覆盖保存三分支。
    private let photoLibrary: any PhotoLibraryAccess

    init(photoLibrary: any PhotoLibraryAccess = IOSPhotoLibraryAccess()) {
        self.photoLibrary = photoLibrary
    }

    /// 渲染 A4 高清图纸为 PNG Data（对应源端 exportPattern 的 renderA4Export → PNG 编码）。
    /// - Parameters:
    ///   - photoPixels: 原图 RGBA 缩略像素（源端 loadPhotoPixels，最大边 560），可空。
    ///   - includeWatermark: ADR-0010 免费版水印开关（true = 带醒目品牌）。
    func renderA4PNG(pattern: BeadPattern,
                     photoPixels: [UInt8]?, photoW: Int, photoH: Int,
                     exportOpts: BeadExportOpts?,
                     includeWatermark: Bool = false) -> Data? {
        let buffer = renderA4Export(pattern: pattern, photoPixels: photoPixels,
                                    photoW: photoW, photoH: photoH, exportOpts: exportOpts,
                                    includeWatermark: includeWatermark)
        let a4 = getA4Size()
        guard let cgImage = Self.makeCGImage(rgba: buffer, width: a4.width, height: a4.height) else {
            return nil
        }
        return UIImage(cgImage: cgImage).pngData()
    }

    /// 渲染 A4 高清图纸为单页 PDF Data（与 renderA4PNG 同一像素渲染结果，仅封装容器不同：
    /// 2480×3508 @300DPI 位图嵌入 595.2×841.8pt 的 A4 页面）。
    func renderA4PDF(pattern: BeadPattern,
                     photoPixels: [UInt8]?, photoW: Int, photoH: Int,
                     exportOpts: BeadExportOpts?,
                     includeWatermark: Bool = false) -> Data? {
        let buffer = renderA4Export(pattern: pattern, photoPixels: photoPixels,
                                    photoW: photoW, photoH: photoH, exportOpts: exportOpts,
                                    includeWatermark: includeWatermark)
        let a4 = getA4Size()
        guard let cgImage = Self.makeCGImage(rgba: buffer, width: a4.width, height: a4.height) else {
            return nil
        }
        // A4 纸 @ 72dpi：210×297mm = 595.2×841.8pt
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()
            UIImage(cgImage: cgImage).draw(in: pageRect)
        }
    }

    /// 保存 PNG 到系统相册（对应源端 createAsset + writePixelMapAsPng）。
    /// 需要 NSPhotoLibraryAddUsageDescription（已配置）。
    /// 权限被拒抛 PhotoLibraryError.savePermissionDenied（P2-1：经协议注入）。
    func saveToPhotoLibrary(pngData: Data) async throws {
        try await photoLibrary.save(imageData: pngData, as: .photo)
    }

    /// 写入分享缓存文件（对应源端 sharePattern 写入 cacheDir/bead_pattern_share.png）。
    func writeShareCache(data: Data, filename: String = "bead_pattern_share.png") throws -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
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
