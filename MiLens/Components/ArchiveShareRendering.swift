//  ArchiveShareRendering —— 手机分页归档模板的离屏渲染与缩略图解码。
//
//  每次只持有一页需要的降采样图片，页完成后由 autoreleasepool 释放中间缓冲；
//  返回 Data/URL 等 Sendable 值，避免把全分辨率 UIImage 跨任务长期持有。

import Foundation
import SwiftUI
import UIKit
import ImageIO
import MiLensKit

struct ArchiveShareRenderedPage: Sendable {
    let url: URL
    let filename: String
    let previewData: Data
    let byteCount: Int
}

struct ArchiveShareRenderedBundle: Sendable {
    let pages: [ArchiveShareRenderedPage]
    let filename: String
    let spec: String
}

enum ArchiveShareRenderOutcome: Sendable {
    case success(ArchiveShareRenderedBundle)
    case failure(String)
    case cancelled
}

enum ArchiveShareRendering {
    static func renderTimeline(
        data: TimelineExportData,
        quality: ExportQuality
    ) async -> ArchiveShareRenderOutcome {
        let pages = ArchiveSharePagination.timelinePages(from: data.months)
        guard !pages.isEmpty else {
            return .failure(String(localized: "timeline.renderFailed"))
        }

        var pathMap: [UUID: String] = [:]
        for entry in data.months.flatMap(\.entries) {
            guard let photoID = entry.photoID,
                  let path = ArchiveSharePagination.preferredImagePath(
                    thumbnailPath: entry.thumbnailPath,
                    photoURI: entry.photoURI
                  ) else { continue }
            pathMap[photoID] = path
        }
        let heroPhotoID = data.months.lazy.flatMap(\.entries).compactMap(\.photoID).first
        var renderedPages: [ArchiveShareRenderedPage] = []

        for (index, page) in pages.enumerated() {
            if Task.isCancelled {
                cleanup(renderedPages)
                return .cancelled
            }
            let filename = String(format: "timeline_export_%02d.jpg", index + 1)
            do {
                let imageMap = autoreleasepool { () -> [UUID: UIImage] in
                    var photoIDs = Set(page.months.flatMap(\.entries).compactMap(\.photoID))
                    if page.isCover, let heroPhotoID { photoIDs.insert(heroPhotoID) }
                    return loadImages(
                        photoIDs: photoIDs,
                        pathMap: pathMap,
                        heroPhotoID: page.isCover ? heroPhotoID : nil
                    )
                }
                let image = try await rasterizeTimelinePage(
                    data: data,
                    page: page,
                    imageMap: imageMap,
                    heroPhotoID: heroPhotoID,
                    pageNumber: index + 1,
                    pageCount: pages.count
                )
                let rendered = try encodeAndCache(
                    image: image,
                    filename: filename,
                    compressionQuality: quality.jpegCompressionQuality
                )
                renderedPages.append(rendered)
            } catch {
                cleanup(renderedPages)
                return .failure(String(localized: "timeline.exportFailedDetail \(error.localizedDescription)"))
            }
        }

        return .success(bundle(
            pages: renderedPages,
            filenameBase: "timeline_export"
        ))
    }

    static func renderAnnualRecap(
        year: Int,
        months: [MonthlyRecap],
        totalPhotoCount: Int,
        pathMap: [UUID: String],
        quality: ExportQuality,
        includeWatermark: Bool = false
    ) async -> ArchiveShareRenderOutcome {
        let pages = ArchiveSharePagination.annualPages(from: months)
        guard !pages.isEmpty else {
            return .failure(String(localized: "recap.renderFailed"))
        }

        let heroPhotoID = months.lazy.flatMap(\.photoIDs).first
        var renderedPages: [ArchiveShareRenderedPage] = []

        for (index, page) in pages.enumerated() {
            if Task.isCancelled {
                cleanup(renderedPages)
                return .cancelled
            }
            let filename = String(format: "recap_%d_%02d.jpg", year, index + 1)
            do {
                let imageMap = autoreleasepool { () -> [UUID: UIImage] in
                    var photoIDs = Set(page.months.flatMap { month in
                        Array(month.photoIDs.prefix(ArchiveShareLayout.photosPerMonth))
                    })
                    if page.isCover, let heroPhotoID { photoIDs.insert(heroPhotoID) }
                    return loadImages(
                        photoIDs: photoIDs,
                        pathMap: pathMap,
                        heroPhotoID: page.isCover ? heroPhotoID : nil
                    )
                }
                let image = try await rasterizeAnnualPage(
                    year: year,
                    page: page,
                    imageMap: imageMap,
                    heroPhotoID: heroPhotoID,
                    totalPhotoCount: totalPhotoCount,
                    totalMonthCount: months.count,
                    pageNumber: index + 1,
                    pageCount: pages.count,
                    includeWatermark: includeWatermark
                )
                let rendered = try encodeAndCache(
                    image: image,
                    filename: filename,
                    compressionQuality: quality.jpegCompressionQuality
                )
                renderedPages.append(rendered)
            } catch {
                cleanup(renderedPages)
                return .failure(String(localized: "recap.exportFailedDetail \(error.localizedDescription)"))
            }
        }

        return .success(bundle(
            pages: renderedPages,
            filenameBase: "recap_\(year)"
        ))
    }

    //  View 协议与 ImageRenderer 在 iOS 17 SDK 均为 main actor 隔离：
    //  画布构造与光栅化必须在主线程；解码（loadImages）与编码落盘（encodeAndCache）
    //  留在并发池，各自包 autoreleasepool，保持逐页释放缓冲的纪律。
    @MainActor
    private static func rasterizeTimelinePage(
        data: TimelineExportData,
        page: TimelineArchiveSharePage,
        imageMap: [UUID: UIImage],
        heroPhotoID: UUID?,
        pageNumber: Int,
        pageCount: Int
    ) throws -> UIImage {
        let canvas = TimelineExportCanvas(
            data: data,
            page: page,
            imageMap: imageMap,
            coverHeroImage: heroPhotoID.flatMap { imageMap[$0] },
            pageNumber: pageNumber,
            pageCount: pageCount
        )
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = ArchiveShareLayout.renderScale
        guard let image = renderer.uiImage else {
            throw ArchiveShareRenderingError.renderFailed
        }
        return image
    }

    @MainActor
    private static func rasterizeAnnualPage(
        year: Int,
        page: AnnualArchiveSharePage,
        imageMap: [UUID: UIImage],
        heroPhotoID: UUID?,
        totalPhotoCount: Int,
        totalMonthCount: Int,
        pageNumber: Int,
        pageCount: Int,
        includeWatermark: Bool
    ) throws -> UIImage {
        let canvas = RecapExportCanvas(
            year: year,
            page: page,
            imageMap: imageMap,
            coverHeroImage: heroPhotoID.flatMap { imageMap[$0] },
            totalPhotoCount: totalPhotoCount,
            totalMonthCount: totalMonthCount,
            pageNumber: pageNumber,
            pageCount: pageCount,
            includeWatermark: includeWatermark
        )
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = ArchiveShareLayout.renderScale
        guard let image = renderer.uiImage else {
            throw ArchiveShareRenderingError.renderFailed
        }
        return image
    }

    private static func encodeAndCache(
        image: UIImage,
        filename: String,
        compressionQuality: Double
    ) throws -> ArchiveShareRenderedPage {
        try autoreleasepool { () -> ArchiveShareRenderedPage in
            guard let data = image.jpegData(compressionQuality: compressionQuality) else {
                throw ArchiveShareRenderingError.renderFailed
            }
            let previewData = downscalePreview(
                image: image,
                maxDimension: ArchiveShareLayout.pageHeight
            ) ?? data
            let url = try BeadExportService().writeShareCache(data: data, filename: filename)
            return ArchiveShareRenderedPage(
                url: url,
                filename: filename,
                previewData: previewData,
                byteCount: data.count
            )
        }
    }

    private static func loadImages(
        photoIDs: Set<UUID>,
        pathMap: [UUID: String],
        heroPhotoID: UUID?
    ) -> [UUID: UIImage] {
        var result: [UUID: UIImage] = [:]
        for photoID in photoIDs {
            guard let path = pathMap[photoID] else { continue }
            let maxPixelSize = photoID == heroPhotoID ? ArchiveShareLayout.pixelWidth : 512
            result[photoID] = loadDownsampled(path: path, maxPixelSize: maxPixelSize)
        }
        return result
    }

    private static func loadDownsampled(path: String, maxPixelSize: Int) -> UIImage? {
        let fileURL: URL
        if path.hasPrefix("file://"), let url = URL(string: path) {
            fileURL = url
        } else {
            fileURL = URL(fileURLWithPath: path)
        }
        let url = fileURL as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func downscalePreview(image: UIImage, maxDimension: CGFloat) -> Data? {
        let pixelSize = CGSize(
            width: CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale)),
            height: CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        )
        let longEdge = max(pixelSize.width, pixelSize.height)
        guard longEdge > maxDimension else {
            return image.jpegData(compressionQuality: 0.85)
        }

        let scale = maxDimension / longEdge
        let targetSize = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).jpegData(
            withCompressionQuality: 0.85
        ) { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func bundle(
        pages: [ArchiveShareRenderedPage],
        filenameBase: String
    ) -> ArchiveShareRenderedBundle {
        let totalBytes = pages.reduce(0) { $0 + $1.byteCount }
        let filename: String
        if pages.count == 1 {
            filename = pages[0].filename
        } else {
            filename = String(format: "%@_01-%02d.jpg", filenameBase, pages.count)
        }
        let spec = "\(pages.count) × \(ArchiveShareLayout.pixelWidth)×\(ArchiveShareLayout.pixelHeight) · JPEG · \(formatByteCount(totalBytes))"
        return ArchiveShareRenderedBundle(pages: pages, filename: filename, spec: spec)
    }

    private static func formatByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func cleanup(_ pages: [ArchiveShareRenderedPage]) {
        for page in pages {
            try? FileManager.default.removeItem(at: page.url)
        }
    }
}

private enum ArchiveShareRenderingError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        String(localized: "recap.renderFailed")
    }
}
