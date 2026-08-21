//  BusinessCardArtwork —— 四套 Namecard 名片版式（预览与导出共用，720×450 基准）。
//
//  Figma 四套模板落地：museum 博物馆典藏 / binding 私人装帧 /
//  gallery 现代画廊 / darkroom 夜间暗房。
//  布局按 Figma 基准坐标绝对定位（±2pt 容差），整体 scaleEffect 随画布缩放——
//  字号、描边、blur 半径、圆角全部随基准坐标一次性缩放，
//  预览与 1440×900（16:10）导出同源。纹理由 CardTextures/CardTexturesB 提供。
//  从 BusinessCardView 拆出（规模守卫，DESIGN.md §6 / AGENTS.md §3）。

import SwiftUI
import UIKit
import MiLensKit

// MARK: - 名片排版（预览与导出共用）

/// 宠物名片版式：四套高级模板共用字段
/// （名/身份/擅长/性格/照护人/MILENS ID/季节/拍摄时间）。
struct BusinessCardArtwork: View {
    let data: PetBusinessCardData
    var avatarImage: UIImage?
    var template: BusinessCardTemplate = .museum
    var includeWatermark: Bool = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / Layout.base, geo.size.height / Layout.baseH)
            card
                .frame(width: Layout.base, height: Layout.baseH)
                .scaleEffect(s)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(Layout.base / Layout.baseH, contentMode: .fit)
    }

    @ViewBuilder
    private var card: some View {
        switch template {
        case .museum: museumNamecard
        case .binding: bindingNamecard
        case .gallery: galleryNamecard
        case .darkroom: darkroomNamecard
        }
    }

    private enum Layout {
        /// Figma 基准尺寸（导出 2× = 1440×900，16:10）。
        static let base: CGFloat = 720
        static let baseH: CGFloat = 450
    }

    // MARK: - 01 Museum 博物馆典藏

    /// 白卡 + 照片 + 书脊细线 + 两段式字段 + 纸纤维 + 右侧墨竹 + 小藏印。
    private var museumNamecard: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            photoFill(w: 320, h: 398, r: 14)
                .place(26, 26, w: 320, h: 398)

            // 书脊细线 + 朱砂短标
            Rectangle().fill(CardInk.hairline)
                .place(372, 26, w: 1, h: 398)
            Rectangle().fill(CardInk.vermilion)
                .place(371, 26, w: 3, h: 40)

            // 右侧纸纤维（文字区避让）+ 墨竹主体
            PaperFibers(
                width: 346, height: 450, baseWidth: 346, baseHeight: 450,
                seed: 20_260_815, density: 0.0018,
                reserved: [28...48, 58...112], layerOpacity: 0.32)
                .place(374, 0, w: 346, h: 450)
            BambooRubbing(
                width: 214, height: 450, baseWidth: 214, baseHeight: 450,
                seed: 7212, layout: .namecardMuseum, layerOpacity: 0.72)
                .place(532, 0, w: 214, h: 450)

            // 头行 + 季节 + 小藏印
            headerLine
                .foregroundStyle(CardInk.taupe)
                .place(402, 30, w: 190, h: 16)
            if !data.seasonLine.isEmpty {
                Text(data.seasonLine)
                    .font(.system(size: 15))
                    .foregroundStyle(CardInk.vermilion)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(631, 30, w: 72, h: 18)
            }
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CardInk.vermilion)
                .frame(width: 16, height: 16)
                .overlay(
                    Text("M")
                        .font(.custom("Fraunces-Bold", size: 10))
                        .foregroundStyle(.white))
                .place(606, 30, w: 16, h: 16)

            Text(data.name)
                .font(.localeDisplayFont(size: 44))
                .foregroundStyle(CardInk.inkBlack)
                .lineLimit(1).minimumScaleFactor(0.5)
                .place(402, 62, w: 240, h: 48)

            // 两段式字段：标签（灰褐小字）/ 值
            if !data.identityLine.isEmpty {
                fieldLabel("身份").place(402, 128, w: 292, h: 14)
                fieldValue(data.identityLine, size: 16).place(402, 146, w: 292, h: 22)
            }
            if !data.tagline.isEmpty {
                fieldLabel("擅长").place(402, 190, w: 292, h: 14)
                Text(data.tagline)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(CardInk.inkBlack)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(402, 208, w: 292, h: 28)
            }
            if !personalityLine.isEmpty {
                fieldLabel("性格").place(402, 258, w: 292, h: 14)
                fieldValue(personalityLine, size: 16).place(402, 276, w: 292, h: 22)
            }
            if !data.milensID.isEmpty {
                fieldLabel("MILENS ID").place(402, 320, w: 292, h: 14)
                Text(data.milensID)
                    .font(.custom("Fraunces-Semibold", size: 16))
                    .foregroundStyle(CardInk.bronze)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(402, 338, w: 292, h: 20)
            }
            if !ownerLine.isEmpty {
                fieldLabel("照护人").place(402, 376, w: 292, h: 14)
                Text(ownerLine)
                    .font(.custom("Fraunces-Semibold", size: 16))
                    .foregroundStyle(CardInk.inkBlack)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(402, 394, w: 292, h: 22)
            }
            watermark(CardInk.taupe.opacity(0.7))
        }
    }

    // MARK: - 02 Binding 私人装帧

    /// 布纹卡 + 铜线装订（织纹带 + 两端装订点）+ 照片 + 内页衬纸 + 铜色细节。
    private var bindingNamecard: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            BookclothGrain(width: 720, height: 450, baseWidth: 720, baseHeight: 450)
                .place(0, 0, w: 720, h: 450)

            // 铜装订线：经纬织纹带 + 中轴铜线 + 两端装订点
            WovenSpine(width: 8, height: 394, baseWidth: 8, baseHeight: 394)
                .place(23, 28, w: 8, h: 394)
            Rectangle().fill(CardInk.bronze)
                .place(26.5, 28, w: 1, h: 394)
            Circle().fill(CardInk.bronze)
                .place(24.5, 25, w: 5, h: 5)
            Circle().fill(CardInk.bronze)
                .place(24.5, 420, w: 5, h: 5)

            photoFill(w: 304, h: 398, r: 6)
                .place(42, 26, w: 304, h: 398)

            // 内页衬纸：铜色透衬 + 轻 blur + 衬页边线
            Rectangle()
                .fill(Color(hex: 0xFCE8DF).opacity(0.2))
                .frame(width: 348, height: 450)
                .blur(radius: 2.5)
                .place(372, -1, w: 348, h: 450)
            Rectangle().fill(CardInk.bronze.opacity(0.5))
                .place(371, 26, w: 1, h: 398)

            headerLine
                .foregroundStyle(CardInk.bronze)
                .place(402, 36, w: 190, h: 16)
            Text(data.name)
                .font(.localeDisplayFont(size: 44))
                .foregroundStyle(CardInk.inkBlack)
                .lineLimit(1).minimumScaleFactor(0.5)
                .place(402, 67, w: 296, h: 48)

            if !data.identityLine.isEmpty {
                Text(data.identityLine)
                    .font(.system(size: 18))
                    .foregroundStyle(CardInk.inkBlack)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(402, 128, w: 292, h: 24)
            }
            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(CardInk.inkBlack)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(402, 191, w: 292, h: 28)
            }
            if !personalityLine.isEmpty {
                Text(personalityLine)
                    .font(.system(size: 16))
                    .foregroundStyle(CardInk.warmGray)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(402, 260, w: 292, h: 22)
            }

            Rectangle().fill(CardInk.hairline)
                .place(402, 334, w: 292, h: 1)
            if !ownerLine.isEmpty {
                Text(ownerLine)
                    .font(.system(size: 16))
                    .foregroundStyle(CardInk.warmGray)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(402, 350, w: 292, h: 22)
            }
            if !data.shotDateLine.isEmpty {
                Text(data.shotDateLine)
                    .font(.system(size: 15))
                    .foregroundStyle(CardInk.bronze)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(402, 399, w: 292, h: 18)
            }
            watermark(CardInk.taupe.opacity(0.7))
        }
    }

    // MARK: - 03 Gallery 现代画廊

    /// 黑场（丝网半调）+ 满版照片 + 朱砂导轨 + 朱砂 ID Block。
    private var galleryNamecard: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            photoFill(w: 440, h: 450, r: 0)
                .place(280, 0, w: 440, h: 450)

            // 黑场 + 半调网点（沿左缘渐弱）+ 朱砂导轨
            Rectangle().fill(CardInk.inkBlack)
                .place(0, 0, w: 280, h: 450)
            Halftone(
                width: 280, height: 450, baseWidth: 280, baseHeight: 450,
                fadeEdge: .leading, layerOpacity: 0.48)
                .place(0, 0, w: 280, h: 450)
            Rectangle().fill(CardInk.vermilion)
                .place(268, 0, w: 12, h: 450)

            headerLine
                .foregroundStyle(.white)
                .place(28, 28, w: 190, h: 16)
            Text(data.name)
                .font(.localeDisplayFont(size: 44))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
                .place(28, 59, w: 224, h: 48)
            if !data.identityLine.isEmpty {
                Text(data.identityLine)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(28, 121, w: 224, h: 22)
            }
            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .place(28, 181, w: 224, h: 64)
            }
            if !personalityLine.isEmpty {
                Text(personalityLine)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(28, 274, w: 224, h: 22)
            }
            if !data.shotDateLine.isEmpty {
                Text(data.shotDateLine)
                    .font(.system(size: 15))
                    .foregroundStyle(CardInk.vermilion)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(28, 398, w: 140, h: 18)
            }

            // 朱砂 ID Block（照护人铭牌）
            if !ownerLine.isEmpty {
                Rectangle().fill(CardInk.vermilion)
                    .place(560, 390, w: 160, h: 60)
                Text(ownerLine)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(577, 400, w: 126, h: 22)
            }
            watermark(.white.opacity(0.55), x: 30, y: 426)
        }
    }

    // MARK: - 04 Darkroom 夜间暗房

    /// 暗房深底 + 安全灯红晕 + 银盐颗粒 + 样片条（齿孔/曝光轨）+ 右栏信息。
    private var darkroomNamecard: some View {
        ZStack(alignment: .topLeading) {
            CardInk.darkBase

            // 安全灯红晕（右下溢出样片后方的暗房光）+ 银盐颗粒
            Ellipse()
                .fill(CardInk.bronze)
                .frame(width: 250, height: 250)
                .blur(radius: 44)
                .place(520, 290, w: 250, h: 250)
            SilverGrain(width: 720, height: 450, baseWidth: 720, baseHeight: 450)
                .place(0, 0, w: 720, h: 450)

            // 样片条：照片 + 齿孔 + 曝光轨 + 分隔线
            photoFill(w: 410, h: 398, r: 6, stroke: CardInk.bronze)
                .place(26, 26, w: 410, h: 398)
            FilmPerforations(width: 16, height: 398, baseWidth: 16, baseHeight: 398)
                .place(420, 26, w: 16, h: 398)
            Rectangle().fill(CardInk.bronze)
                .place(26, 26, w: 3, h: 398)
            Rectangle().fill(CardInk.mist.opacity(0.35))
                .place(462, 26, w: 1, h: 398)

            // 右栏信息（x = 488）
            headerLine
                .foregroundStyle(CardInk.bronze)
                .place(488, 39, w: 190, h: 16)
            Text(data.name)
                .font(.localeDisplayFont(size: 44))
                .foregroundStyle(CardInk.paperWhite)
                .lineLimit(1).minimumScaleFactor(0.5)
                .place(488, 69, w: 206, h: 48)
            if !data.identityLine.isEmpty {
                Text(data.identityLine)
                    .font(.system(size: 16))
                    .foregroundStyle(CardInk.mist)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(488, 130, w: 206, h: 22)
            }
            if !data.tagline.isEmpty {
                Text(data.tagline)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(CardInk.paperWhite)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .place(488, 188, w: 206, h: 56)
            }
            if !personalityLine.isEmpty {
                Text(personalityLine)
                    .font(.system(size: 16))
                    .foregroundStyle(CardInk.mist)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(488, 278, w: 206, h: 22)
            }
            Rectangle().fill(CardInk.mist.opacity(0.4))
                .place(488, 337, w: 206, h: 1)
            if !ownerLine.isEmpty {
                Text(ownerLine)
                    .font(.system(size: 16))
                    .foregroundStyle(CardInk.mist)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(488, 352, w: 206, h: 22)
            }
            watermark(CardInk.mist.opacity(0.7))
        }
    }

    // MARK: - 共用组件

    /// 头行（Fraunces 字标，四套共用文案）。
    private var headerLine: some View {
        Text("MILENS PET PROFILE")
            .font(.custom("Fraunces-Semibold", size: 13))
            .tracking(1.2)
    }

    /// 两段式字段标签（灰褐小字）。
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(CardInk.taupe)
    }

    /// 两段式字段值（墨黑正文）。
    private func fieldValue(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(CardInk.inkBlack)
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    /// 性格行（标签以「 · 」连接）。
    private var personalityLine: String {
        data.tags.joined(separator: " · ")
    }

    /// 照护人行（「照护人｜」前缀，空则不渲染）。
    private var ownerLine: String {
        PetBusinessCardLogic.ownerLine(data.ownerName)
    }

    /// 照片位：等比填充 + 圆角裁剪 + 可选描边；无头像回退爪印占位。
    private func photoFill(
        w: CGFloat, h: CGFloat, r: CGFloat, stroke: Color? = nil
    ) -> some View {
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(CardInk.hairline.opacity(0.5))
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: min(w, h) * 0.22))
                        .foregroundStyle(CardInk.taupe)
                }
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(stroke ?? .clear, lineWidth: 1))
    }

    /// 免费版水印（右下角；gallery 黑场内改用左下角坐标）。
    @ViewBuilder
    private func watermark(_ color: Color, x: CGFloat = 612, y: CGFloat = 432) -> some View {
        if includeWatermark {
            Text("MiLens")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 80, height: 12, alignment: .trailing)
                .place(x, y, w: 80, h: 12)
        }
    }
}

// MARK: - 左上角绝对定位

private extension View {
    /// 以 (x, y) 为左上角放置 w×h 视图（Figma 基准坐标系）。
    func place(_ x: CGFloat, _ y: CGFloat, w: CGFloat, h: CGFloat, align: Alignment = .leading) -> some View {
        frame(width: w, height: h, alignment: align)
            .position(x: x + w / 2, y: y + h / 2)
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
