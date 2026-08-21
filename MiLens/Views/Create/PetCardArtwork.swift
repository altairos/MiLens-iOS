//  PetCardArtwork —— 四套 Keepsake 纪念卡版式（预览与导出共用，360×450 基准）。
//
//  Figma「Keepsake Cards · Premium Directions」四套模板落地：
//  museum 博物馆典藏 / binding 私人装帧 / gallery 现代画廊 / darkroom 夜间暗房。
//  布局按 Figma 基准坐标绝对定位（±2pt 容差），整体 scaleEffect 随画布缩放——
//  字号、描边、blur 半径、圆角全部随基准坐标一次性缩放，预览与 1080×1350 导出同源。
//  纹理由 CardTextures/CardTexturesB 提供（固定 seed，逐像素可复现）。

import SwiftUI
import MiLensKit

/// 宠物纪念卡版式：四套高级模板共用四字段文案（名/物种/季节/注释行）。
struct PetCardArtwork: View {
    let image: UIImage
    let content: PetCardContent
    /// 卡片模板（决定排版分支）。
    var template: PetCardTemplate = .museum
    /// 免费版导出显示半透明「MiLens」水印。
    var includeWatermark: Bool = false
    /// 季节行（「YYYY · 季」，View 层按拍摄日期算好传入；空则不渲染）。
    var season: String = ""
    /// 一行注释（Figma 07 Annotation Register；优先于日期行显示）。
    var annotation: String = ""

    /// 注释行文本：注释优先，未填写时回退日期行（里程碑/生日文案不丢失）。
    private var noteLine: String {
        annotation.isEmpty ? content.dateLine : annotation
    }

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
        case .museum: museumKeepsake
        case .binding: bindingKeepsake
        case .gallery: galleryKeepsake
        case .darkroom: darkroomKeepsake
        }
    }

    private enum Layout {
        /// Figma 基准尺寸（导出 3×）。
        static let base: CGFloat = 360
        static let baseH: CGFloat = 450
    }

    // MARK: - 01 Museum 博物馆典藏

    /// 白卡 + 照片 + 纸纤维 + 竹拓 + 朱砂藏印 + 朱砂季节。
    private var museumKeepsake: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            photoFill(w: 308, h: 286, r: 14)
                .place(26, 26, w: 308, h: 286)
            PaperFibers(width: 360, height: 138, reserved: [8...120])
                .place(0, 312, w: 360, h: 138)
            BambooRubbing(width: 70, height: 55)
                .place(290, 395, w: 70, h: 55)

            // 朱砂藏印 + 档案头行
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(CardInk.vermilion)
                .frame(width: 20, height: 20)
                .overlay(
                    Text("M")
                        .font(.custom("Fraunces-Bold", size: 12))
                        .foregroundStyle(.white))
                .place(33, 323, w: 20, h: 20)
            headerLine
                .foregroundStyle(CardInk.taupe)
                .place(62, 325, w: 190, h: 16)

            Rectangle().fill(CardInk.hairline)
                .place(26, 357, w: 308, h: 1)

            Text(content.title)
                .font(.localeDisplayFont(size: 32))
                .foregroundStyle(CardInk.inkBlack)
                .lineLimit(1).minimumScaleFactor(0.5)
                .place(33, 363, w: 160, h: 36)
            if !season.isEmpty {
                Text(season)
                .font(.localeDisplayFont(size: 30))
                    .foregroundStyle(CardInk.vermilion)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(201, 365, w: 130, h: 34)
            }
            Text(content.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(CardInk.warmGray)
                .lineLimit(1).minimumScaleFactor(0.7)
                .place(33, 412, w: 260, h: 17)
            noteLineView(CardInk.taupe)
                .place(33, 435, w: 240, h: 15)
            watermark(CardInk.taupe.opacity(0.7))
        }
    }

    // MARK: - 02 Binding 私人装帧

    /// 布纹卡 + 铜线装订（织纹带 + 两端装订点）+ 照片 + 铜色护页衬纸。
    private var bindingKeepsake: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            BookclothGrain(width: 360, height: 450)
                .place(0, 0, w: 360, h: 450)

            // 铜装订线：经纬织纹带 + 中轴铜线 + 两端装订点
            WovenSpine(width: 8, height: 394)
                .place(23, 28, w: 8, h: 394)
            Rectangle().fill(CardInk.bronze)
                .place(26.5, 28, w: 1, h: 394)
            Circle().fill(CardInk.bronze)
                .place(24.5, 25, w: 5, h: 5)
            Circle().fill(CardInk.bronze)
                .place(24.5, 420, w: 5, h: 5)

            photoFill(w: 282, h: 292, r: 6)
                .place(42, 28, w: 282, h: 292)

            // 护页衬纸：铜色透衬 + 轻blur + 铜描边
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(hex: 0xD26342).opacity(0.18))
                .frame(width: 138, height: 180)
                .blur(radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(CardInk.bronze, lineWidth: 1))
                .place(203, 233, w: 138, h: 180)

            Text(String(localized: "petcard.museum.label"))
                .font(.localeDisplayFont(size: 12))
                .foregroundStyle(CardInk.taupe)
                .place(42, 355, w: 140, h: 16)
            Text("MiLens")
                .font(.custom("Fraunces-Semibold", size: 11))
                .foregroundStyle(CardInk.bronze.opacity(0.55))
                .place(44, 397, w: 60, h: 14)

            // 护页内三行（季节/物种/名）
            if !season.isEmpty {
                Text(season)
                    .font(.localeDisplayFont(size: 18))
                    .foregroundStyle(CardInk.bronze)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(211, 326, w: 122, h: 22)
            }
            Text(content.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(CardInk.warmGray)
                .lineLimit(1).minimumScaleFactor(0.6)
                .place(211, 348, w: 122, h: 16)
            Text(content.title)
                .font(.localeDisplayFont(size: 22))
                .foregroundStyle(CardInk.inkBlack)
                .lineLimit(1).minimumScaleFactor(0.5)
                .place(211, 368, w: 122, h: 26)
            noteLineView(CardInk.taupe)
                .place(42, 435, w: 250, h: 15)
            watermark(CardInk.taupe.opacity(0.7))
        }
    }

    // MARK: - 03 Gallery 现代画廊

    /// 满版照片 + 墨黑展签带（丝网半调）+ 朱砂导轨 + 白色大字。
    private var galleryKeepsake: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            photoFill(w: 360, h: 300, r: 0)
                .place(0, 0, w: 360, h: 300)

            // 黑色展签带 + 半调网点 + 朱砂导轨
            Rectangle().fill(CardInk.inkBlack)
                .place(0, 300, w: 360, h: 150)
            Halftone(width: 360, height: 150, fadeEdge: .top)
                .place(0, 300, w: 360, h: 150)
            Rectangle().fill(CardInk.vermilion)
                .place(0, 300, w: 10, h: 150)
            Rectangle().fill(CardInk.vermilion)
                .place(278, 323, w: 56, h: 3)

            headerLine
                .foregroundStyle(.white)
                .place(26, 318, w: 190, h: 16)
            if !season.isEmpty {
                Text(season)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CardInk.vermilion)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(283, 338, w: 51, h: 15)
            }
            Text(content.title)
                .font(.localeDisplayFont(size: 42))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
                .place(26, 342, w: 240, h: 48)
            Text(content.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.7)
                .place(26, 407, w: 150, h: 17)
            Text(String(localized: "petcard.gallery.label"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .place(224, 407, w: 110, h: 17)
            noteLineView(.white.opacity(0.7))
                .place(26, 435, w: 240, h: 15)
            watermark(.white.opacity(0.55))
        }
    }

    // MARK: - 04 Darkroom 夜间暗房

    /// 暗房深底 + 安全灯红晕 + 银盐颗粒 + 样片条（齿孔/曝光轨/帧号）。
    private var darkroomKeepsake: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x2C2722)

            // 安全灯红晕（中心溢出样片后方的暗房光）
            Ellipse()
                .fill(CardInk.bronze)
                .frame(width: 250, height: 250)
                .blur(radius: 44)
                .place(65, 175, w: 250, h: 250)
            SilverGrain(width: 360, height: 450)
                .place(0, 0, w: 360, h: 450)

            // 样片条：照片 + 齿孔 + 曝光轨 + 帧号 Tab
            photoFill(w: 308, h: 306, r: 6, stroke: CardInk.bronze)
                .place(26, 26, w: 308, h: 306)
            FilmPerforations(width: 16, height: 306)
                .place(318, 42, w: 16, h: 306)
            Rectangle().fill(CardInk.bronze)
                .place(26, 26, w: 3, h: 306)
            Text("01")
                .font(.custom("Fraunces-Bold", size: 13))
                .foregroundStyle(CardInk.darkBase)
                .frame(width: 58, height: 18)
                .background(RoundedRectangle(cornerRadius: 2).fill(CardInk.bronze))
                .place(276, 26, w: 58, h: 18)

            Rectangle().fill(CardInk.mist.opacity(0.4))
                .place(26, 347, w: 308, h: 1)

            headerLine
                .foregroundStyle(CardInk.bronze)
                .place(26, 354, w: 190, h: 16)
            Text(content.title)
                .font(.localeDisplayFont(size: 32))
                .foregroundStyle(CardInk.paperWhite)
                .lineLimit(1).minimumScaleFactor(0.5)
                .place(26, 374, w: 160, h: 36)
            if !season.isEmpty {
                Text(season)
                    .font(.localeDisplayFont(size: 28))
                    .foregroundStyle(CardInk.linenWhite)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .place(210, 378, w: 124, h: 32)
            }
            Text(content.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(CardInk.mist)
                .lineLimit(1).minimumScaleFactor(0.7)
                .place(27, 418, w: 260, h: 17)
            noteLineView(CardInk.mist.opacity(0.8))
                .place(27, 435, w: 230, h: 15)
            watermark(CardInk.mist.opacity(0.55))
        }
    }

    // MARK: - 通用元素

    /// 档案头行（Fraunces 小型大写风格标签）。
    private var headerLine: some View {
        Text("MILENS · LIFE ARCHIVE")
            .font(.custom("Fraunces-Semibold", size: 12))
            .tracking(1.2)
            .lineLimit(1)
    }

    /// 注释行（Figma 未定义位置，统一基准 y=435；空则不渲染）。
    @ViewBuilder
    private func noteLineView(_ color: Color) -> some View {
        if !noteLine.isEmpty {
            Text(noteLine)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// 免费水印（右下角小字，语义沿用 ADR-0010）。
    @ViewBuilder
    private func watermark(_ color: Color) -> some View {
        if includeWatermark {
            Text("MiLens")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(color)
                .place(226, 437, w: 108, h: 12, align: .trailing)
        }
    }

    /// 照片按指定框填充裁剪（scaledToFill + clipped + 圆角/描边）。
    private func photoFill(w: CGFloat, h: CGFloat, r: CGFloat, stroke: Color? = nil) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: w, height: h)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay {
                if let stroke {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1)
                }
            }
    }
}

// MARK: - 基准坐标定位

private extension View {
    /// 按 Figma 基准坐标（左上角）绝对定位；`align` 控制框内对齐（默认左对齐）。
    func place(
        _ x: CGFloat, _ y: CGFloat, w: CGFloat, h: CGFloat, align: Alignment = .leading
    ) -> some View {
        frame(width: w, height: h, alignment: align)
            .position(x: x + w / 2, y: y + h / 2)
    }
}
