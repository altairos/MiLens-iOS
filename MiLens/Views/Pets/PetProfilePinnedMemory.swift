//  PetProfilePinnedMemory —— PetProfileView 的置顶记忆区块。
//  从 PetProfileView.swift 拆出（ADR-0011 §5 规模守卫拆分批次）：
//  数据选择（PinnedMemory.pick）+ 展示视图（PinnedMemorySection）。
//  对照 Figma「02·伙伴档案」#I319:1101;296:595-608。

import SwiftUI

/// 置顶记忆数据：isPinned 事件 → 最近用户记录 → 随机照片回退。
struct PinnedMemory {
    let title: String
    let note: String
    let dateLabel: String
    let photoPath: String?
}

extension PinnedMemory {
    /// 取置顶的 PetEvent（isPinned）或最近用户记录（sourceType=="user"），
    /// 回退随机一张照片（每次进入页面从全部照片中随机选一张，增加新鲜感）。
    /// randomIndex 由宿主 load() 时固定一次（同 HomeHeroLogic.selectHeroPhoto 的种子参数化模式），
    /// body 重算不再重新随机，直到下次 load 才换一张。
    static func pick(pet: Pet, photos: [Photo], randomIndex: Int) -> PinnedMemory? {
        // 优先 isPinned 事件
        let pinnedEvents = pet.events.filter { $0.isPinned }
        // 其次用户记录
        let userEvents = pet.events.filter { $0.sourceType == "user" && !$0.body.isEmpty }
        let candidates = pinnedEvents.isEmpty ? userEvents : pinnedEvents

        if let ev = candidates.sorted(by: { $0.eventDate > $1.eventDate }).first {
            let cal = Calendar.current
            let m = cal.component(.month, from: ev.eventDate)
            let d = cal.component(.day, from: ev.eventDate)
            let relatedPhoto = ev.relatedPhotoID.flatMap { rid in photos.first { $0.id == rid } }
            let fallbackPhoto = photos.isEmpty ? nil : photos[randomIndex % photos.count]
            let chosen = relatedPhoto ?? fallbackPhoto
            let path = chosen?.thumbnailPath.isEmpty == false ? chosen?.thumbnailPath : chosen?.uri
            return PinnedMemory(
                title: ev.title,
                note: ev.body,
                dateLabel: "RECENT · " + String(format: "%02d.%02d", m, d),
                photoPath: path
            )
        }

        // 回退：按宿主固定的随机索引取一张（每次 load 不同，body 重算稳定）
        guard !photos.isEmpty else { return nil }
        let photo = photos[randomIndex % photos.count]
        let dateLabel: String
        if let takenAt = photo.takenAt {
            let cal = Calendar.current
            dateLabel = "RECENT · " + String(format: "%02d.%02d", cal.component(.month, from: takenAt), cal.component(.day, from: takenAt))
        } else {
            dateLabel = "RECENT"
        }
        let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
        return PinnedMemory(
            title: photo.note.isEmpty ? String(localized: "pet.profile.pinned.recent") : photo.note,
            note: "",
            dateLabel: dateLabel,
            photoPath: path
        )
    }
}

/// 置顶记忆展示：Section 标签 + Fold index 竖线 + 日期 overline + 文楷标题 + 缩略图。
struct PinnedMemorySection: View {
    let pinned: PinnedMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section 标签（独立头部行，对照 #I319:1101;296:595）
            Text(String(localized: "pet.profile.pinned.section"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.horizontal, 24)

            // Fold index + 内容行（对照 #I319:1101;296:604-598）
            HStack(alignment: .top, spacing: 15) {
                // 左侧珊瑚竖线 4pt（panel x=16 起，对照 Pinned Fold Index #I319:1101;296:604）
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 4)
                    .cornerRadius(Radius.accentRail)

                VStack(alignment: .leading, spacing: 6) {
                    // 日期 overline（对照 #I319:1101;296:608）
                    Text(pinned.dateLabel)
                        .font(.editorialOverline)
                        .tracking(0.4)
                        .foregroundStyle(Color.milensActionPrimary)
                    // 文楷标题（对照 #I319:1101;296:597）
                    Text(pinned.title)
                        .font(.localeDisplayFont(size: 16, relativeTo: .body))
                        .foregroundStyle(Color.milensTextPrimary)
                    // 正文（对照 #I319:1101;296:598）
                    if !pinned.note.isEmpty {
                        Text(pinned.note)
                            .font(.bodySecondary)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                }

                Spacer(minLength: 12)

                // 右侧缩略图 122×86（对照 Pinned Memory Photo #I319:1101;296:596）
                if let path = pinned.photoPath {
                    ThumbnailImage(path: path)
                        .scaledToFill()
                        .frame(width: 122, height: 86)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 24)
        }
    }
}
