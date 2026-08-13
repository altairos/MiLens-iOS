//  PetProfileComponents —— 宠物档案页拆出的独立展示组件。
//  从 PetProfileView 拆出（规模守卫，DESIGN.md §6 / AGENTS.md §3）。
//  对照 Figma「02·伙伴档案」#319 与 #307 iPad Adaptive Layout。

import SwiftUI

// MARK: - 出血肖像 Hero

/// 肖像大图 + 底部渐变 + 文楷名字 + 副标题 + More 按钮。
/// 对照 Figma #319:1096-1100。
/// - Parameter height: Hero 高度（iPhone 315pt / iPad 700pt）。
struct PortraitHero: View {
    /// 肖像数据源（avatarPath 或最新照片缩略图；nil 用 emoji 占位）。
    let path: String?
    /// 无肖像时的 emoji 占位（物种 emoji）。
    let emojiPlaceholder: String
    /// 宠物名字。
    let name: String
    /// 副标题（已含 foregroundStyle）。
    let subtitle: Text
    /// Hero 高度。
    let height: CGFloat
    /// 编辑路由用的宠物 ID。
    let petID: UUID

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 大图 / 占位
            if let path {
                ThumbnailImage(path: path)
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
            } else {
                Color.milensAccentSoft
                    .frame(height: height)
                    .overlay(
                        Text(emojiPlaceholder)
                            .font(.system(size: 72)) // ui-token:ok 肖像占位装饰大字
                    )
            }

            // 底部渐变（对照 Portrait Gradient #319:1097）
            LinearGradient(
                colors: [Color.black.opacity(0), Color.milensHeroGradientEnd.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: min(height * 0.54, 330))
            .frame(maxHeight: .infinity, alignment: .bottom)

            // 名字 + 副标题（对照 #319:1099-1100）
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.custom("LXGWWenKai-Regular", size: height > 400 ? 42 : 38,
                                  relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                subtitle
                    .font(.bodySecondary)
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.leading, 28)
            .padding(.bottom, height > 400 ? 32 : 16)

            // 右上角 More Action 按钮（对照 #319:1098）
            VStack {
                HStack {
                    Spacer()
                    Menu {
                        NavigationLink(value: Route.petEdit(petID: petID)) {
                            Label(String(localized: "pet.profile.edit"), systemImage: "pencil")
                        }
                    } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "ellipsis")
                                    .font(.system(size: Sizing.iconSm, weight: .semibold))
                                    .foregroundStyle(Color.milensInk)
                            )
                    }
                }
                Spacer()
            }
            .padding(.trailing, 20)
            .padding(.top, height > 400 ? 48 : 56)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height > 400 ? 28 : 0, style: .continuous))
    }
}

// MARK: - Archive Continuity Note（对照 #307:680-684）

/// iPad 左列底部的生命档案连续性标语：LIFE 编号 + 文楷引言 + 说明 + 基线。
struct ArchiveContinuityNote: View {
    let pet: Pet

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIFE 02 · \(PetDisplayLogic.daysTogether(from: pet.adoptionDay)) DAYS")
                .font(.custom("JacquesFrancois-Regular", size: 10))
                .tracking(0.4)
                .foregroundStyle(Color.milensActionPrimary)
            Text("将散落的记忆，\n装订成流动的时间之河")
                .font(.custom("LXGWWenKai-Regular", size: 28, relativeTo: .title2))
                .foregroundStyle(Color.milensTextPrimary)
            Text("从第一张照片、第一次出门，到每天微小的变化；所有片段都回到它发生的时间里。")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Color.milensBorder)
                .frame(width: 180, height: 1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 24)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Timeline Continuation 卡片（对照 #307:715-721）

/// iPad 右列底部的时间线续页卡片：下一页日期 + 标题 + 副文 + 打开链接。
struct TimelineContinuationCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT LEAF · 2026.06")
                .font(.custom("JacquesFrancois-Regular", size: 10))
                .tracking(0.4)
                .foregroundStyle(Color.milensActionPrimary)
            Text("06. 18")
                .font(.custom("Fraunces-Semibold", size: 34))
                .foregroundStyle(Color.milensTextPrimary)
            Text("夏天开始前的傍晚")
                .font(.custom("LXGWWenKai-Regular", size: 20))
                .foregroundStyle(Color.milensTextPrimary)
            Text("一条风很大的路，一次主动跑进海水里的勇气。")
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
            Rectangle()
                .fill(Color.milensBorder)
                .frame(height: 1)
            NavigationLink(value: Route.timeline) {
                HStack(spacing: 4) {
                    Text("打开完整生命时间线")
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensActionPrimary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: Sizing.iconSm, weight: .semibold))
                        .foregroundStyle(Color.milensActionPrimary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - 四列统计单项

/// Archive Panel 四列统计的单项：大数字 + 小标签。
/// 对照 Figma Archive Stat #I319:1101;296:617-626。
/// 实现已收敛到可复用组件 ArchiveStatView（UI-DESIGN.md §5.6 契约），
/// 此处保留为语义别名以便 PetProfileView 调用点不需改动。
struct ArchiveStatItem: View {
    let value: String
    let label: String
    /// 可选单位后缀。
    var unit: String? = nil

    var body: some View {
        ArchiveStatView(value: value, label: label, unit: unit)
    }
}
