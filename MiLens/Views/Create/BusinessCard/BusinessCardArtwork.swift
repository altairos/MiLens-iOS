//  BusinessCardArtwork —— 宠物名片排版组件（预览与导出共用）+ FlowLayout 流式布局。
//  从 BusinessCardView 拆出（规模守卫，DESIGN.md §6 / AGENTS.md §3）。
//  字号与间距按画布宽度比例缩放，预览与导出同源。

import SwiftUI
import UIKit
import MiLensKit

// MARK: - 名片排版（预览与导出共用）

/// 宠物名片版式：头像 + 名字 + 身份信息 + 标签胶囊 + 简介 + 主人称呼。
/// 字号与间距按画布宽度比例缩放（预览与导出同源）。
struct BusinessCardArtwork: View {
    let data: PetBusinessCardData
    var avatarImage: UIImage?
    var template: BusinessCardTemplate = .standard
    var includeWatermark: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            switch template {
            case .standard:
                standardLayout(w: w, h: h)
            case .elegant:
                elegantLayout(w: w, h: h)
            case .playful:
                playfulLayout(w: w, h: h)
            case .minimal:
                minimalLayout(w: w, h: h)
            }
        }
        .aspectRatio(
            Double(PetBusinessCardLogic.exportWidth) / Double(PetBusinessCardLogic.exportHeight),
            contentMode: .fit)
    }

    // MARK: - 标准（居中头像 + 信息列 + 标签）

    private func standardLayout(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: w * 0.04) {
            Spacer(minLength: h * 0.06)

            avatarView(size: w * 0.28)

            Text(data.name)
                .font(.custom("LXGWWenKai-Regular", size: w * 0.08))
                .foregroundStyle(Color.milensTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(subtitleLine)
                .font(.system(size: w * 0.034, weight: .regular, design: .rounded))
                .foregroundStyle(Color.milensTextSecondary)

            if !data.tags.isEmpty {
                tagFlow(w: w)
            }

            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: w * 0.036, weight: .light, design: .rounded))
                    .foregroundStyle(Color.milensTextPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, w * 0.1)
            }

            Spacer()

            if !ownerLine.isEmpty {
                Text(ownerLine)
                    .font(.system(size: w * 0.03, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.milensTextTertiary)
                    .padding(.bottom, h * 0.04)
            }

            watermarkIfIncluded(w: w)
        }
        .frame(width: w, height: h)
        .background(Color.milensCard)
    }

    // MARK: - 优雅（衬线留白 + 大号名字）

    private func elegantLayout(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: w * 0.05) {
            Spacer(minLength: h * 0.1)

            Text(data.name)
                .font(.custom("LXGWWenKai-Regular", size: w * 0.12))
                .foregroundStyle(Color.milensTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            avatarView(size: w * 0.22)

            Text(subtitleLine)
                .font(.system(size: w * 0.032, weight: .light, design: .serif))
                .foregroundStyle(Color.milensTextSecondary)
                .tracking(w * 0.005)

            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: w * 0.034, weight: .light, design: .serif))
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            watermarkIfIncluded(w: w)
        }
        .frame(width: w, height: h)
        .background(Color.milensCard)
    }

    // MARK: - 活泼（圆角彩底 + 标签网格）

    private func playfulLayout(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: w * 0.035) {
            Spacer(minLength: h * 0.05)

            ZStack {
                Circle()
                    .fill(Color.milensAccentSoft)
                    .frame(width: w * 0.32, height: w * 0.32)
                avatarView(size: w * 0.26)
            }

            Text("\(data.name) \u{1F43E}")
                .font(.custom("LXGWWenKai-Regular", size: w * 0.075))
                .foregroundStyle(Color.milensTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(subtitleLine)
                .font(.system(size: w * 0.032, weight: .medium, design: .rounded))
                .foregroundStyle(Color.milensTextSecondary)

            if !data.tags.isEmpty {
                tagFlow(w: w)
            }

            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: w * 0.034, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.milensTextPrimary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            watermarkIfIncluded(w: w)
        }
        .frame(width: w, height: h)
        .background(Color.milensCard)
    }

    // MARK: - 极简（纯文字）

    private func minimalLayout(w: CGFloat, h: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: w * 0.03) {
            Spacer(minLength: h * 0.1)

            Text(data.name)
                .font(.custom("LXGWWenKai-Regular", size: w * 0.1))
                .foregroundStyle(Color.milensTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(subtitleLine)
                .font(.system(size: w * 0.032, weight: .regular, design: .default))
                .foregroundStyle(Color.milensTextSecondary)

            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: w * 0.034, weight: .regular, design: .default))
                    .foregroundStyle(Color.milensTextPrimary)
            }

            if !data.tags.isEmpty {
                Text(data.tags.joined(separator: " · "))
                    .font(.system(size: w * 0.03, weight: .light, design: .default))
                    .foregroundStyle(Color.milensTextTertiary)
            }

            Spacer()

            if !ownerLine.isEmpty {
                Text(ownerLine)
                    .font(.system(size: w * 0.028, weight: .regular, design: .default))
                    .foregroundStyle(Color.milensTextTertiary)
            }

            watermarkIfIncluded(w: w)
        }
        .padding(.horizontal, w * 0.12)
        .frame(width: w, height: h, alignment: .topLeading)
        .background(Color.milensCard)
    }

    // MARK: - 共用组件

    @ViewBuilder
    private func avatarView(size: CGFloat) -> some View {
        if let avatarImage {
            Image(uiImage: avatarImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.milensAccentSoft)
                    .frame(width: size, height: size)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Color.milensTextTertiary)
            }
        }
    }

    private func tagFlow(w: CGFloat) -> some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(data.tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: w * 0.03, weight: .medium, design: .rounded))
                    .padding(.horizontal, w * 0.025)
                    .padding(.vertical, w * 0.012)
                    .background(Color.milensAccentSoft)
                    .foregroundStyle(Color.milensTextPrimary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, w * 0.08)
    }

    @ViewBuilder
    private func watermarkIfIncluded(w: CGFloat) -> some View {
        if includeWatermark {
            Text("MiLens")
                .font(.system(size: w * 0.026, weight: .medium, design: .rounded))
                .foregroundStyle(Color.milensTextTertiary)
                .padding(.bottom, w * 0.04)
        }
    }

    private var subtitleLine: String {
        PetBusinessCardLogic.subtitleLine(
            speciesName: data.speciesName, breed: data.breed,
            genderName: data.genderName, ageText: data.ageText)
    }

    private var ownerLine: String {
        PetBusinessCardLogic.ownerLine(data.ownerName)
    }
}

// MARK: - 简易流式布局（标签胶囊换行）

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        _ = arrange(subviews: subviews, maxWidth: maxWidth, totalHeight: &totalHeight)
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var totalHeight: CGFloat = 0
        let positions = arrange(subviews: subviews, maxWidth: bounds.width, totalHeight: &totalHeight)
        for (index, position) in positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat, totalHeight: inout CGFloat) -> [(x: CGFloat, y: CGFloat)] {
        var positions: [(x: CGFloat, y: CGFloat)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append((x, y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight = y + rowHeight
        return positions
    }
}
