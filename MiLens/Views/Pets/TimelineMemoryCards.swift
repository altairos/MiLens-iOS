//  TimelineMemoryCards —— 时间线记忆卡片组件（照片/文本/作品三种）。
//  从 TimelineView 拆出（规模守卫，DESIGN.md §6 / AGENTS.md §3）。
//  对照 Figma「03·生命时间线」#140:362-411。

import SwiftUI

// MARK: - 照片记忆卡片

/// 照片记忆：大图 + 左上「照片记忆」标签 + 日期 + 文楷标题 + 正文。
/// 对照 Figma #140:362-367。
struct PhotoMemoryCard: View {
    let entry: TimelineEntry

    var body: some View {
        NavigationLink(value: Route.photoView(photoID: entry.photoID ?? UUID())) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // 大图 + 左上角标签
                ZStack(alignment: .topLeading) {
                    if !entry.thumbnailPath.isEmpty {
                        ThumbnailImage(path: entry.thumbnailPath)
                            .scaledToFill()
                            .frame(height: 176)
                            .clipped()
                    } else if !entry.photoURI.isEmpty {
                        ThumbnailImage(path: entry.photoURI)
                            .scaledToFill()
                            .frame(height: 176)
                            .clipped()
                    } else {
                        // 无图占位
                        Rectangle()
                            .fill(Color.milensGrouped)
                            .frame(height: 176)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(Color.milensTextTertiary)
                            )
                    }

                    // 左上角「照片记忆」标签
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.milensActionPrimary)
                            .frame(width: 22, height: 2)
                        Text(String(localized: "timeline.memoryType.photo"))
                            .font(.editorialOverline)
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                    .padding(.leading, 14)
                    .padding(.top, 14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // 日期（珊瑚）
                Text(entry.subtitle)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensActionPrimary)

                // 文楷标题
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.custom("LXGWWenKai-Regular", size: 18, relativeTo: .title3))
                        .foregroundStyle(Color.milensTextPrimary)
                }

                // 正文（对照 #140:367，13pt regular secondary）
                if !entry.bodyText.isEmpty {
                    Text(entry.bodyText)
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 文本记忆卡片

/// 文本记忆：浅粉底 #FCE8DF + 左侧珊瑚 rail + 日期 + 正文。
/// 对照 Figma #140:369-371 + #143:411 rail。
struct TextMemoryCard: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(spacing: 0) {
            // 左侧珊瑚 rail（3pt）
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)
            // 内容区
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(entry.subtitle)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensActionPrimary)
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                }
                if !entry.bodyText.isEmpty {
                    Text(entry.bodyText)
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .padding(.vertical, 18)
            Spacer()
        }
        .background(Color.milensAccentWash)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - 作品记录卡片

/// 作品记录：左侧珊瑚 rail + 作品预览 + 类型标签 + 标题 + 来源说明。
/// 对照 Figma #140:374-411。作品预览优先回链来源照片缩略图（relatedPhotoID），
/// 无来源照片时回退到 7x7 拼豆占位网格（拼豆像素级预览属后续功能）。
struct WorkRecordCard: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(spacing: 0) {
            // 左侧珊瑚 rail（3pt）
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)
            // 内容区
            HStack(spacing: Spacing.md) {
                // 作品预览（方形）：优先来源照片缩略图，回退拼豆占位网格
                preview
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    // 作品记录类型标签
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.milensActionPrimary)
                            .frame(width: 22, height: 2)
                        Text(String(localized: "timeline.memoryType.work"))
                            .font(.editorialOverline)
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                    Text(entry.title)
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                    // 日期（珊瑚）
                    Text(entry.subtitle)
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensActionPrimary)
                    // 来源说明：优先正文，其次「由一张照片生成」
                    if !entry.bodyText.isEmpty {
                        Text(entry.bodyText)
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                            .lineLimit(2)
                    } else if entry.photoID != nil {
                        Text(String(localized: "timeline.work.fromPhoto"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                }
                Spacer()
            }
            .padding(16)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.milensBorder).frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.milensBorder).frame(height: 0.5)
        }
    }

    /// 作品预览：优先来源照片缩略图，回退拼豆占位网格。
    @ViewBuilder
    private var preview: some View {
        if !entry.thumbnailPath.isEmpty {
            ThumbnailImage(path: entry.thumbnailPath)
        } else if !entry.photoURI.isEmpty {
            ThumbnailImage(path: entry.photoURI)
        } else {
            beadGridPlaceholder
        }
    }

    /// 7x7 拼豆占位网格（无来源照片时回退；设计稿配色 #C74729 / #2E2924 交替）。
    private var beadGridPlaceholder: some View {
        let cols = 7
        let rows = 7
        let beadSize: CGFloat = 8
        let gap: CGFloat = 3
        return VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<cols, id: \.self) { c in
                        Circle()
                            .fill((r + c) % 3 == 0 ? Color.milensActionPrimary : Color.milensInk)
                            .frame(width: beadSize, height: beadSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.milensGrouped)
    }
}
