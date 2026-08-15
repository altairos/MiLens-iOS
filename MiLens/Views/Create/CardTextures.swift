//  CardTextures —— 四套卡片模板（museum/binding/gallery/darkroom）的纸面与印刷纹理。
//
//  全部纹理按「Figma 基准坐标 × scale」绘制（scale = 显示宽 / 基准宽）：
//  预览与 ImageRenderer 导出同源，逐像素一致。随机性统一走 Mulberry32 固定 seed，
//  重跑结果不变。纸纤维/竹拓算法移植自 tools/figma-plugin/milens-museum-fix/code.js
//  （G10 精修版）；布纹/织纹/半调/银盐/齿孔按 EL 设计意图新写近似。
//  画布固定 hex 色（不接 Any/Dark token），保证导出不受系统外观影响。

import SwiftUI

// MARK: - 固定色板（Figma 实测）

/// 十六进制色值直转（UInt32 字面量，区别于 RedPacket 的 String 版本）。
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}

/// 四套模板画布固定色（导出一致性优先，不随系统外观切换）。
enum CardInk {
    static let vermilion = Color(hex: 0xBC4727) // 朱砂（导轨/季节/藏印）
    static let inkBlack = Color(hex: 0x1F1B18) // 墨黑（主文字/黑带/竹拓墨）
    static let warmGray = Color(hex: 0x6B625B) // 暖灰（物种行）
    static let taupe = Color(hex: 0xA89F97) // 灰褐（头行/字段标签）
    static let hairline = Color(hex: 0xE5DFD8) // 分隔线
    static let bronze = Color(hex: 0x7C3F30) // 铜红（装订线/描边）
    static let darkBase = Color(hex: 0x2C2722) // 暗房深底
    static let paperWhite = Color(hex: 0xF2EBE3) // 暗房纸白
    static let linenWhite = Color(hex: 0xDFD7CF) // 暗房亚麻白
    static let mist = Color(hex: 0xB5A89C) // 暗房雾灰
    static let fiberInk = Color(hex: 0x85796B) // 纸纤维暖灰褐
}

// MARK: - 确定性伪随机

/// mulberry32 确定性伪随机（UInt32 溢出运算对应 JS 位运算语义）。
/// 同一 seed 序列在预览与导出两次渲染中完全一致。
struct Mulberry32 {
    private var a: UInt32

    init(seed: UInt32) { a = seed }

    /// [0, 1) 均匀分布。
    mutating func next() -> Double {
        a &+= 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

// MARK: - 通用绘制辅助

/// 按基准坐标系缩放 Canvas 上下文（纹理内部全部用 Figma 基准坐标绘制）。
private func scaleContext(
    _ ctx: inout GraphicsContext, width: CGFloat, height: CGFloat,
    baseWidth: CGFloat, baseHeight: CGFloat
) {
    let s = min(width / baseWidth, height / baseHeight)
    ctx.scaleBy(x: s, y: s)
}

// MARK: - 纸纤维（museum 底纹）

/// 手工纸纤维：云状浆斑 + 全向长弧纤维（18% 分叉）+ 短绒 + 断续帘纹 + 纤维结。
/// `reserved` 为基准坐标系的文字保护区——纵区内只留帘纹与浆斑，杂纤维全部避开。
/// 算法逐层对应 code.js buildFibersSvg（rnd 消费顺序一致，保证与 Figma 版同构）。
struct PaperFibers: View {
    let width: CGFloat
    let height: CGFloat
    /// Figma 基准尺寸（Keepsake 360×138 / Namecard 346×450）。
    var baseWidth: CGFloat = 360
    var baseHeight: CGFloat = 138
    var seed: UInt32 = 20_260_814
    var density: Double = 0.0038
    var reserved: [ClosedRange<CGFloat>] = []
    /// 整层不透明度（Figma 节点 opacity：Keepsake 0.5 / Namecard 0.32）。
    var layerOpacity: Double = 0.5

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            scaleContext(&ctx, width: width, height: height,
                         baseWidth: baseWidth, baseHeight: baseHeight)
            ctx.opacity = layerOpacity
            draw(&ctx)
        }
    }

    private func inReserved(_ y: CGFloat) -> Bool {
        reserved.contains { y >= $0.lowerBound && y <= $0.upperBound }
    }

    private func draw(_ ctx: inout GraphicsContext) {
        var rnd = Mulberry32(seed: seed)
        let w = baseWidth
        let h = baseHeight
        let ink = CardInk.fiberInk

        // 1. 云状浆斑：3 层同心椭圆叠透明度模拟软边（手工纸分布不均）
        let clouds = 2 + Int((rnd.next() * 2).rounded())
        for _ in 0..<clouds {
            let cx = rnd.next() * w
            let cy = rnd.next() * h
            let rx = 34 + rnd.next() * 26
            let rot = rnd.next() * 180
            for (k, op) in [(1.0, 0.028), (0.7, 0.04), (0.42, 0.05)] {
                let rw = rx * k
                let rect = CGRect(x: cx - rw, y: cy - rw * 0.34, width: rw * 2, height: rw * 0.68)
                let spot = Path(ellipseIn: rect).applying(
                    CGAffineTransform(translationX: -cx, y: -cy)
                        .rotated(by: rot * .pi / 180)
                        .translatedBy(x: cx, y: cy))
                ctx.fill(spot, with: .color(ink.opacity(op)))
            }
        }

        // 2. 主纤维（全向长弧 + 18% 斜出短枝）——纸面结构主视觉
        let n1 = Int((w * h * density).rounded())
        for _ in 0..<n1 {
            let f = makeFiber(&rnd, w: w, h: h, lenMin: 22, lenMax: 56)
            if inReserved(f.midY) { continue }
            ctx.stroke(f.path, with: .color(ink.opacity(0.32)),
                       style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            if rnd.next() < 0.18 {
                var branch = Path()
                branch.move(to: f.mid)
                let a = Double(f.angle) + (rnd.next() < 0.5 ? 1 : -1) * (0.9 + rnd.next() * 0.7)
                let len = 7 + rnd.next() * 9
                branch.addLine(to: CGPoint(
                    x: f.mid.x + CGFloat(cos(a) * len),
                    y: f.mid.y + CGFloat(sin(a) * len)))
                ctx.stroke(branch, with: .color(ink.opacity(0.26)),
                           style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            }
        }

        // 3. 短绒纤维（细密底噪）
        let n2 = Int((Double(n1) * 0.8).rounded())
        for _ in 0..<n2 {
            let f = makeFiber(&rnd, w: w, h: h, lenMin: 9, lenMax: 20)
            if inReserved(f.midY) { continue }
            ctx.stroke(f.path, with: .color(ink.opacity(0.18)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }

        // 4. 帘纹（约 44pt 一行的断续残影，保护区也保留——纸的潜意识骨架）
        let rows = max(3, Int((h / 44).rounded()))
        for i in 0..<rows {
            let y = ((Double(i) + 0.5) * h) / Double(rows) + (rnd.next() - 0.5) * 6
            let segs = rnd.next() < 0.55 ? 1 : 2
            for _ in 0..<segs {
                let x0 = rnd.next() * w * 0.5
                let x1 = min(w, x0 + w * (0.24 + rnd.next() * 0.36))
                let dy = (rnd.next() - 0.5) * 2.2
                var path = Path()
                path.move(to: CGPoint(x: x0, y: y))
                path.addCurve(
                    to: CGPoint(x: x1, y: y + dy * 0.4),
                    control1: CGPoint(x: (x0 + x1) / 3, y: y + dy),
                    control2: CGPoint(x: (x0 + x1) * 2 / 3, y: y - dy))
                ctx.stroke(path, with: .color(ink.opacity(0.1)),
                           style: StrokeStyle(lineWidth: 0.7))
            }
        }

        // 5. 纤维结（短粗小段，最少量）
        let n3 = Int((w * h * 0.0006).rounded())
        for _ in 0..<n3 {
            let x = rnd.next() * w
            let y = rnd.next() * h
            if inReserved(y) { continue }
            let a = rnd.next() * .pi
            let dx = cos(a) * 2.2
            let dy = sin(a) * 2.2
            var path = Path()
            path.move(to: CGPoint(x: x - dx, y: y - dy))
            path.addLine(to: CGPoint(x: x + dx, y: y + dy))
            ctx.stroke(path, with: .color(ink.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }
}

/// 全向纤维弧线：随机方向二次曲线（Q），返回路径与中点/角度供分叉与保护区判断。
private func makeFiber(
    _ rnd: inout Mulberry32, w: CGFloat, h: CGFloat,
    lenMin: CGFloat, lenMax: CGFloat
) -> (path: Path, mid: CGPoint, midY: CGFloat, angle: CGFloat) {
    let x0 = rnd.next() * w
    let y0 = rnd.next() * h
    let len = lenMin + rnd.next() * (lenMax - lenMin)
    let ang = rnd.next() * .pi * 2
    let bow = (rnd.next() - 0.5) * 16
    let x1 = x0 + cos(ang) * len
    let y1 = y0 + sin(ang) * len
    let mid = CGPoint(
        x: (x0 + x1) / 2 + cos(ang + .pi / 2) * bow,
        y: (y0 + y1) / 2 + sin(ang + .pi / 2) * bow)
    var path = Path()
    path.move(to: CGPoint(x: x0, y: y0))
    path.addQuadCurve(to: CGPoint(x: x1, y: y1), control: mid)
    return (path, mid, mid.y, ang)
}

// MARK: - 布纹（binding 全幅底纹）

/// 装帧布纹：经纬两组断续细线交织 + 少量纤维结（近似 EL「Cloth Grain」）。
/// 层透明度对应 Figma 节点 op 0.16。
struct BookclothGrain: View {
    let width: CGFloat
    let height: CGFloat
    var baseWidth: CGFloat = 360
    var baseHeight: CGFloat = 450
    var seed: UInt32 = 20_260_820
    var layerOpacity: Double = 0.16

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            scaleContext(&ctx, width: width, height: height,
                         baseWidth: baseWidth, baseHeight: baseHeight)
            ctx.opacity = layerOpacity
            draw(&ctx)
        }
    }

    private func draw(_ ctx: inout GraphicsContext) {
        var rnd = Mulberry32(seed: seed)
        let w = baseWidth
        let h = baseHeight
        let ink = CardInk.fiberInk

        // 经线（竖向断续，段长随机、间隙随机）
        var x = rnd.next() * 2.0
        while x < w {
            var y = rnd.next() * 4
            while y < h {
                let seg = 5 + rnd.next() * 8
                var path = Path()
                path.move(to: CGPoint(x: x + (rnd.next() - 0.5) * 0.4, y: y))
                path.addLine(to: CGPoint(x: x + (rnd.next() - 0.5) * 0.4, y: y + seg))
                ctx.stroke(path, with: .color(ink.opacity(0.3 + rnd.next() * 0.25)),
                           style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
                y += seg + 1.5 + rnd.next() * 2.5
            }
            x += 2.5 + rnd.next() * 0.8
        }
        // 纬线（横向断续，略稀）
        var y0 = rnd.next() * 2.0
        while y0 < h {
            var x0 = rnd.next() * 4
            while x0 < w {
                let seg = 4 + rnd.next() * 7
                var path = Path()
                path.move(to: CGPoint(x: x0, y: y0 + (rnd.next() - 0.5) * 0.4))
                path.addLine(to: CGPoint(x: x0 + seg, y: y0 + (rnd.next() - 0.5) * 0.4))
                ctx.stroke(path, with: .color(ink.opacity(0.22 + rnd.next() * 0.2)),
                           style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
                x0 += seg + 1.2 + rnd.next() * 2.2
            }
            y0 += 2.8 + rnd.next() * 0.8
        }
    }
}

// MARK: - 书脊织纹（binding 装订线）

/// 铜线书脊两侧的经纬织纹：中轴经线断续 + 横向纬线起伏交错
/// （近似 EL「Woven Spine Texture」，宽约 8pt 的窄带）。
struct WovenSpine: View {
    let width: CGFloat
    let height: CGFloat
    var baseWidth: CGFloat = 8
    var baseHeight: CGFloat = 394
    var seed: UInt32 = 20_260_821

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            scaleContext(&ctx, width: width, height: height,
                         baseWidth: baseWidth, baseHeight: baseHeight)
            var rnd = Mulberry32(seed: seed)
            let w = baseWidth
            let ink = CardInk.bronze

            // 纬线：y 步进 3.5pt，全带宽，正弦起伏 + 微抖（编织的上下交错感）
            var y = 1.5
            var row = 0
            while y < baseHeight {
                let phase = Double(row) * 0.9 + rnd.next() * 0.4
                let sway = 0.5 + rnd.next() * 0.3
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y + sin(phase) * sway))
                path.addQuadCurve(
                    to: CGPoint(x: w, y: y + sin(phase + .pi) * sway),
                    control: CGPoint(x: w / 2, y: y + sin(phase + .pi / 2) * sway * 1.6))
                ctx.stroke(path, with: .color(ink.opacity(0.32 + rnd.next() * 0.22)),
                           style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                y += 3.5
                row += 1
            }
            // 中轴经线：断续竖线压在纬线上
            var yy = rnd.next() * 3
            while yy < baseHeight {
                let seg = 6 + rnd.next() * 10
                var path = Path()
                path.move(to: CGPoint(x: w / 2 + (rnd.next() - 0.5) * 0.5, y: yy))
                path.addLine(to: CGPoint(x: w / 2 + (rnd.next() - 0.5) * 0.5, y: yy + seg))
                ctx.stroke(path, with: .color(ink.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                yy += seg + 1.5 + rnd.next() * 2
            }
        }
    }
}

// MARK: - 丝网半调（gallery 黑带/黑场）

/// 丝网印刷网点：规则网格 + 微抖动，网点大小沿 `fadeEdge` 反方向渐弱。
/// 点色为米白（深底上的印刷网目反光）。
struct Halftone: View {
    enum FadeEdge { case top, leading }

    let width: CGFloat
    let height: CGFloat
    var baseWidth: CGFloat = 360
    var baseHeight: CGFloat = 150
    var seed: UInt32 = 20_260_822
    /// 网格单元（基准坐标 pt）。
    var cell: CGFloat = 6
    var fadeEdge: FadeEdge = .top
    var layerOpacity: Double = 0.5

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            scaleContext(&ctx, width: width, height: height,
                         baseWidth: baseWidth, baseHeight: baseHeight)
            ctx.opacity = layerOpacity
            var rnd = Mulberry32(seed: seed)
            let w = baseWidth
            let h = baseHeight
            let ink = CardInk.paperWhite

            let cols = Int(w / cell)
            let rows = Int(h / cell)
            for r in 0...rows {
                for c in 0...cols {
                    let x = (Double(c) + 0.5) * cell + (rnd.next() - 0.5) * 0.9
                    let y = (Double(r) + 0.5) * cell + (rnd.next() - 0.5) * 0.9
                    let grad: Double
                    switch fadeEdge {
                    case .top: grad = 1 - y / h
                    case .leading: grad = 1 - x / w
                    }
                    let radius = cell * (0.14 + 0.22 * grad)
                    let rect = CGRect(x: x - radius, y: y - radius,
                                      width: radius * 2, height: radius * 2)
                    ctx.fill(Path(ellipseIn: rect),
                             with: .color(ink.opacity(0.12 + 0.3 * grad)))
                }
            }
        }
    }
}

// MARK: - 银盐颗粒（darkroom 全幅）

/// 暗房银盐颗粒：浅色小点密布（长尾透明度——多数极淡、少数亮斑），
/// 叠在深底样片上模拟卤化银感光颗粒。
struct SilverGrain: View {
    let width: CGFloat
    let height: CGFloat
    var baseWidth: CGFloat = 360
    var baseHeight: CGFloat = 450
    var seed: UInt32 = 20_260_823
    var layerOpacity: Double = 0.54

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            scaleContext(&ctx, width: width, height: height,
                         baseWidth: baseWidth, baseHeight: baseHeight)
            ctx.opacity = layerOpacity
            var rnd = Mulberry32(seed: seed)
            let n = Int((baseWidth * baseHeight * 0.022).rounded())
            let ink = CardInk.paperWhite
            for _ in 0..<n {
                let x = rnd.next() * baseWidth
                let y = rnd.next() * baseHeight
                let r = 0.35 + rnd.next() * 0.75
                let tail = rnd.next() * rnd.next() // 长尾：多数淡
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.1 + tail * 0.45)))
            }
        }
    }
}

// MARK: - 胶片齿孔（darkroom 样片条）

/// 胶片齿孔列：圆角矩形按固定孔距竖排（近似 35mm 胶片边孔）。
/// 规则几何，无随机。
struct FilmPerforations: View {
    let width: CGFloat
    let height: CGFloat
    var baseWidth: CGFloat = 16
    var baseHeight: CGFloat = 306
    var layerOpacity: Double = 0.46

    private let hole = CGSize(width: 5.6, height: 4.2)
    private let pitch: CGFloat = 17.6

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            scaleContext(&ctx, width: width, height: height,
                         baseWidth: baseWidth, baseHeight: baseHeight)
            ctx.opacity = layerOpacity
            let ink = CardInk.darkBase
            let count = Int(baseHeight / pitch)
            for i in 0...count {
                let y = 4 + CGFloat(i) * pitch
                let rect = CGRect(
                    x: (baseWidth - hole.width) / 2, y: y,
                    width: hole.width, height: hole.height)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2.1), with: .color(ink))
            }
        }
    }
}
