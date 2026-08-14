//  CardTexturesB —— 竹叶墨拓纹理（museum 模板专用，CardTextures 的姊妹文件）。
//
//  算法移植自 tools/figma-plugin/milens-museum-fix/code.js buildBambooSvg
//  （2026-08-15 五修：照真墨竹图重构墨阶与结构）：
//  淡墨宽竿（三条平行笔道拼宽竿，缝隙=竖向飞白）+ 浓墨横钩节 + 浓墨细枝有节
//  + 细长叶（约 4.5:1）交叉叠压；墨阶 叶 0.8/0.45/0.26 > 枝节 0.5-0.55 > 竿 0.11-0.13。
//  rnd 消费顺序与 JS 完全一致，同一 seed 布局逐笔同构。
//  布局坐标为纹理自身基准坐标（Keepsake 70×55 / Namecard 214×450）。

import SwiftUI

// MARK: - 墨笔数据模型

/// 一笔墨：填充（叶）或描边（枝/节），dash 为虚线（断口洇墨）。
struct InkStroke {
    var path: Path
    var width: CGFloat = 1
    var opacity: Double = 0.5
    var fill = false
    var dash: [CGFloat]? = nil
    var dashPhase: CGFloat = 0
}

// MARK: - 竹拓布局参数

/// 单片竹叶规格（ang 度 / len 长 / tone 墨阶 0 浓 1 中 2 淡）。
struct BambooLeafSpec {
    let ang: Double
    let len: Double
    let tone: Int
}

/// 叶组：共用一个生长点的「个字形」叶簇。
struct BambooGroupSpec {
    let x: Double
    let y: Double
    let leaves: [BambooLeafSpec]
}

/// 细梢：竿节到叶组锚点的细枝（中段两折点）。
struct BambooTwigSpec {
    let from: CGPoint
    let to: CGPoint
    var w: Double? = nil
}

/// 淡墨主竿（root→tip，宽线性渐变，nodes 为 0-1 节位）。
struct BambooStalkSpec {
    let root: CGPoint
    let tip: CGPoint
    let wBase: Double
    let wTop: Double
    let nodes: [Double]
}

/// 浓墨细竿/细枝折线。
struct BambooBranchSpec {
    let pts: [CGPoint]
    let w: Double
}

/// 一幅竹拓的完整布局（z 序：淡竿 → 浓细竿 → 细梢 → 叶）。
struct BambooLayoutSpec {
    var stalk: BambooStalkSpec? = nil
    var darkStalk: BambooBranchSpec? = nil
    var twigs: [BambooTwigSpec] = []
    var groups: [BambooGroupSpec] = []

    /// Keepsake 右下角小簇（70×55，seed 7211）：一根细梢 + 梢头/梢中两簇叶，无竿。
    static let keepsakeCorner = BambooLayoutSpec(
        twigs: [BambooTwigSpec(from: CGPoint(x: 66, y: 18), to: CGPoint(x: 30, y: 33))],
        groups: [
            BambooGroupSpec(x: 30, y: 33, leaves: [
                BambooLeafSpec(ang: 140, len: 26, tone: 0),
                BambooLeafSpec(ang: 172, len: 22, tone: 0),
                BambooLeafSpec(ang: 108, len: 18, tone: 1),
                BambooLeafSpec(ang: 205, len: 15, tone: 2),
            ]),
            BambooGroupSpec(x: 52, y: 25, leaves: [
                BambooLeafSpec(ang: 96, len: 16, tone: 1),
                BambooLeafSpec(ang: 132, len: 13, tone: 2),
            ]),
        ])

    /// Namecard 右侧墨竹主体（214×450，seed 7212）：淡墨宽竿三节 + 浓墨细竿
    /// 右侧并行 + 细梢伸向六簇叶（真墨竹图式）。
    static let namecardMuseum = BambooLayoutSpec(
        stalk: BambooStalkSpec(
            root: CGPoint(x: 64, y: 456), tip: CGPoint(x: 118, y: -6),
            wBase: 15, wTop: 10.5, nodes: [0.2, 0.48, 0.76]),
        darkStalk: BambooBranchSpec(
            pts: [CGPoint(x: 170, y: 456), CGPoint(x: 152, y: 356), CGPoint(x: 140, y: 262),
                  CGPoint(x: 130, y: 168), CGPoint(x: 122, y: 84)],
            w: 2.4),
        twigs: [
            BambooTwigSpec(from: CGPoint(x: 75, y: 364), to: CGPoint(x: 44, y: 340)),
            BambooTwigSpec(from: CGPoint(x: 90, y: 234), to: CGPoint(x: 150, y: 214)),
            BambooTwigSpec(from: CGPoint(x: 105, y: 105), to: CGPoint(x: 62, y: 84)),
            BambooTwigSpec(from: CGPoint(x: 105, y: 105), to: CGPoint(x: 164, y: 62)),
            BambooTwigSpec(from: CGPoint(x: 130, y: 168), to: CGPoint(x: 96, y: 142)),
        ],
        groups: [
            BambooGroupSpec(x: 44, y: 340, leaves: [ // 节1 梢头·左垂簇
                BambooLeafSpec(ang: 150, len: 34, tone: 0),
                BambooLeafSpec(ang: 178, len: 30, tone: 1),
                BambooLeafSpec(ang: 118, len: 24, tone: 1),
                BambooLeafSpec(ang: 205, len: 20, tone: 2),
            ]),
            BambooGroupSpec(x: 150, y: 214, leaves: [ // 节2 梢头·右展簇
                BambooLeafSpec(ang: 20, len: 36, tone: 0),
                BambooLeafSpec(ang: 52, len: 30, tone: 1),
                BambooLeafSpec(ang: -6, len: 26, tone: 1),
                BambooLeafSpec(ang: 82, len: 22, tone: 2),
            ]),
            BambooGroupSpec(x: 62, y: 84, leaves: [ // 节3 双梢·左上簇
                BambooLeafSpec(ang: 160, len: 32, tone: 0),
                BambooLeafSpec(ang: 128, len: 26, tone: 1),
                BambooLeafSpec(ang: 192, len: 24, tone: 2),
            ]),
            BambooGroupSpec(x: 164, y: 62, leaves: [ // 节3 双梢·右上簇
                BambooLeafSpec(ang: 30, len: 30, tone: 0),
                BambooLeafSpec(ang: 62, len: 24, tone: 1),
                BambooLeafSpec(ang: 2, len: 22, tone: 2),
            ]),
            BambooGroupSpec(x: 96, y: 142, leaves: [ // 浓细竿中段·左簇
                BambooLeafSpec(ang: 140, len: 28, tone: 0),
                BambooLeafSpec(ang: 170, len: 24, tone: 1),
                BambooLeafSpec(ang: 108, len: 18, tone: 2),
            ]),
            BambooGroupSpec(x: 152, y: 356, leaves: [ // 浓细竿下节·右小簇
                BambooLeafSpec(ang: 40, len: 26, tone: 1),
                BambooLeafSpec(ang: 72, len: 20, tone: 2),
            ]),
        ])
}

// MARK: - 墨笔生成（逐层对应 code.js）

enum BambooInkBuilder {

    /// 按布局生成全部墨笔（z 序即数组序）。
    static func build(layout: BambooLayoutSpec, seed: UInt32) -> [InkStroke] {
        var rnd = Mulberry32(seed: seed)
        var strokes: [InkStroke] = []
        if let stalk = layout.stalk {
            strokes.append(contentsOf: stalkInk(&rnd, stalk))
        }
        if let dark = layout.darkStalk {
            strokes.append(contentsOf: branchInk(&rnd, dark.pts, dark.w))
        }
        for twig in layout.twigs {
            strokes.append(contentsOf: twigInk(&rnd, twig))
        }
        for group in layout.groups {
            strokes.append(contentsOf: groupLeaves(&rnd, group))
        }
        return strokes
    }

    /// 单片竹叶轮廓：基窄、约 25% 最宽、先端急尖，叶身横弯（cv）+ 略下垂。
    private static func leafPath(
        x: Double, y: Double, len: Double, angDeg: Double, wid: Double, cv: Double
    ) -> Path {
        let rad = angDeg * .pi / 180
        let dx = cos(rad)
        let dy = sin(rad)
        let nx = -dy // 法向
        let ny = dx
        let tx = x + dx * len + nx * len * cv // 叶尖横弯
        let ty = y + dy * len + ny * len * cv + len * 0.05 // 略下垂
        func p(_ t: Double, _ off: Double) -> CGPoint {
            CGPoint(x: x + dx * len * t + nx * off, y: y + dy * len * t + ny * off)
        }
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        path.addCurve(to: CGPoint(x: tx, y: ty),
                      control1: p(0.18, wid * 0.95), control2: p(0.5, wid * 0.4))
        path.addCurve(to: CGPoint(x: x, y: y),
                      control1: p(0.52, -wid * 0.65), control2: p(0.2, -wid * 0.5))
        path.closeSubpath()
        return path
    }

    /// 叶组：每叶 4 层——洇墨垫底（放大淡）→ 主叶 → 叶缘洇毛（断口虚线轮廓）
    /// → 笔毛擦影（错位窄半透明叶）。叠压处半透明自然加深=积墨。
    private static func groupLeaves(_ rnd: inout Mulberry32, _ group: BambooGroupSpec) -> [InkStroke] {
        var strokes: [InkStroke] = []
        for lf in group.leaves {
            let len = lf.len * (0.94 + rnd.next() * 0.12)
            let wid = len * 0.22 // 细长叶 ~4.5:1
            let ang = lf.ang + (rnd.next() - 0.5) * 16 // 角度扰动破规律排布
            let cv = (rnd.next() - 0.5) * 0.2 // 叶身横弯方向/幅度随机
            let op: Double = lf.tone == 0 ? 0.8 : (lf.tone == 1 ? 0.45 : 0.26)
            // 洇墨垫底：放大半透明（叶缘墨洇）
            strokes.append(InkStroke(
                path: leafPath(x: group.x, y: group.y, len: len * 1.05, angDeg: ang, wid: wid * 1.15, cv: cv),
                opacity: op * 0.15, fill: true))
            // 主叶
            strokes.append(InkStroke(
                path: leafPath(x: group.x, y: group.y, len: len, angDeg: ang, wid: wid, cv: cv),
                opacity: op, fill: true))
            // 叶缘洇毛：断口轮廓笔（墨从叶缘洇出的碎毛边）
            strokes.append(InkStroke(
                path: leafPath(x: group.x, y: group.y, len: len, angDeg: ang, wid: wid, cv: cv),
                width: 1.3,
                opacity: op * 0.22,
                dash: [1.6 + rnd.next() * 1.4, 2 + rnd.next() * 2],
                dashPhase: rnd.next() * 3))
            // 笔毛擦影：错位窄半透明叶（叶缘笔毛分叉感）
            strokes.append(InkStroke(
                path: leafPath(x: group.x + 0.8, y: group.y + 0.6, len: len * 0.96,
                               angDeg: ang + 2.5, wid: wid * 0.75, cv: cv),
                opacity: op * 0.35, fill: true))
        }
        return strokes
    }

    /// 竹节：浓墨横钩笔。横笔带随机倾角，两端钩笔为外弯 Q 曲线（真画钩有弹性）。
    private static func nodeMark(
        _ rnd: inout Mulberry32,
        x: Double, y: Double, w: Double,
        hx: Double, hy: Double, sx: Double, sy: Double, op: Double
    ) -> [InkStroke] {
        let tilt = (rnd.next() - 0.5) * 0.14
        let ca = cos(tilt)
        let sa = sin(tilt)
        let hx2 = hx * ca - hy * sa
        let hy2 = hx * sa + hy * ca
        let hw = (w / 2) * (0.9 + rnd.next() * 0.2)
        let x0 = x - hx2 * hw
        let y0 = y - hy2 * hw
        let x1 = x + hx2 * hw
        let y1 = y + hy2 * hw
        let bow = w * 0.16
        let hk = w * (0.14 + rnd.next() * 0.1)

        func horizontal(_ width: Double, _ strokeOp: Double, dash: [CGFloat]? = nil) -> InkStroke {
            var path = Path()
            path.move(to: CGPoint(x: x0, y: y0))
            path.addQuadCurve(
                to: CGPoint(x: x1, y: y1),
                control: CGPoint(x: x + sx * bow, y: y + sy * bow))
            // 仅洇垫笔消费 dashoffset 随机数（与 code.js 消费次数一致）
            let phase: CGFloat = dash != nil ? rnd.next() * 3 : 0
            return InkStroke(path: path, width: width, opacity: strokeOp, dash: dash, dashPhase: phase)
        }
        func hook(from hx: Double, _ hy: Double, flip: Double) -> InkStroke {
            var path = Path()
            path.move(to: CGPoint(x: hx, y: hy))
            path.addQuadCurve(
                to: CGPoint(x: hx + sx * hk, y: hy + sy * hk),
                control: CGPoint(x: hx + sx * hk * 0.4 + flip * hx2 * w * 0.1,
                                 y: hy + sy * hk * 0.4 + flip * hy2 * w * 0.1))
            return InkStroke(path: path, width: w * 0.32, opacity: op)
        }
        // 洇垫（断口虚线宽笔）→ 主笔 → 两端外弯钩
        return [
            horizontal(w * 0.5, 0.16, dash: [1.8, 2.4]),
            horizontal(w * 0.24, op),
            hook(from: x0, y0, flip: -1),
            hook(from: x1, y1, flip: 1),
        ]
    }

    /// 淡墨主竿：三条平行笔道拼宽竿（笔道间细缝=竖向飞白丝），节位画浓墨横钩。
    private static func stalkInk(_ rnd: inout Mulberry32, _ st: BambooStalkSpec) -> [InkStroke] {
        let rx = st.tip.x - st.root.x
        let ry = st.tip.y - st.root.y
        let l = max((rx * rx + ry * ry).squareRoot(), 1)
        let ux = rx / l
        let uy = ry / l
        let nx = -uy // 法向（横笔方向）
        let ny = ux
        let sx = -ux // 钩向（朝根/下）
        let sy = -uy
        var strokes: [InkStroke] = []

        let offs = [-0.31, 0.0, 0.31]
        let ws = [0.36, 0.4, 0.36]
        let ops = [0.11, 0.13, 0.11]
        for si in 0..<3 {
            for seg in 0..<2 {
                // 笔锋参差：起/收笔沿竿向随机伸缩（齐头齐尾读作几何圆柱）
                var t0 = Double(seg) / 2
                var t1 = Double(seg + 1) / 2
                if seg == 0 { t0 -= rnd.next() * 0.025 }
                if seg == 1 { t1 += rnd.next() * 0.025 }
                let tm = (t0 + t1) / 2
                let wSeg = (st.wBase + (st.wTop - st.wBase) * tm) * ws[si]
                let off = offs[si] * (st.wBase + (st.wTop - st.wBase) * tm)
                let a = CGPoint(x: st.root.x + rx * t0 + nx * off, y: st.root.y + ry * t0 + ny * off)
                let b = CGPoint(x: st.root.x + rx * t1 + nx * off, y: st.root.y + ry * t1 + ny * off)
                let bow = (rnd.next() - 0.5) * 3
                var path = Path()
                path.move(to: a)
                path.addQuadCurve(
                    to: b,
                    control: CGPoint(x: (a.x + b.x) / 2 + nx * bow, y: (a.y + b.y) / 2 + ny * bow))
                strokes.append(InkStroke(path: path, width: wSeg, opacity: ops[si]))
            }
        }
        // 边缘溢笔：竿缘外断口淡笔（笔毛出界破整齐边缘）
        for o in [-0.46, 0.46] {
            let off = o * st.wBase
            var path = Path()
            path.move(to: CGPoint(x: st.root.x + nx * off, y: st.root.y + ny * off))
            path.addLine(to: CGPoint(
                x: st.tip.x + nx * off * (st.wTop / st.wBase),
                y: st.tip.y + ny * off * (st.wTop / st.wBase)))
            strokes.append(InkStroke(
                path: path, width: st.wBase * 0.22, opacity: 0.07,
                dash: [5 + rnd.next() * 5, 4 + rnd.next() * 6], dashPhase: rnd.next() * 8))
        }
        // 竹节浓墨横钩
        for t in st.nodes {
            let x = st.root.x + rx * t
            let y = st.root.y + ry * t
            strokes.append(contentsOf: nodeMark(
                &rnd, x: x, y: y,
                w: (st.wBase + (st.wTop - st.wBase) * t) * 0.95,
                hx: nx, hy: ny, sx: sx, sy: sy, op: 0.55))
        }
        return strokes
    }

    /// 浓墨细枝/细竿：分段、节间留断口、节处顿笔钩；每段拆两小段粗→细，
    /// 并垫一道宽淡洇边（破铁丝感）。
    private static func branchInk(_ rnd: inout Mulberry32, _ pts: [CGPoint], _ w: Double) -> [InkStroke] {
        var strokes: [InkStroke] = []
        for i in 0..<(pts.count - 1) {
            let a = pts[i]
            let b = pts[i + 1]
            let ddx = b.x - a.x
            let ddy = b.y - a.y
            let l = max((ddx * ddx + ddy * ddy).squareRoot(), 1)
            let ux = ddx / l
            let uy = ddy / l
            let gap: Double = i > 0 ? 1.6 : 0
            let px = a.x + ux * gap
            let py = a.y + uy * gap
            let bow = (rnd.next() - 0.5) * 4
            let m = CGPoint(x: (px + b.x) / 2 - uy * bow, y: (py + b.y) / 2 + ux * bow)
            let wSeg = w * (1 - Double(i) * 0.14)
            // 洇边垫笔：断口宽虚线（笔毛洇墨碎边）
            var bleed = Path()
            bleed.move(to: CGPoint(x: px, y: py))
            bleed.addQuadCurve(to: b, control: m)
            strokes.append(InkStroke(
                path: bleed, width: wSeg * 2.4, opacity: 0.1,
                dash: [2 + rnd.next() * 2, 3 + rnd.next() * 3], dashPhase: rnd.next() * 4))
            // 主笔：粗→细两小段
            var first = Path()
            first.move(to: CGPoint(x: px, y: py))
            first.addQuadCurve(
                to: m,
                control: CGPoint(x: (px + m.x) / 2, y: (py + m.y) / 2))
            strokes.append(InkStroke(path: first, width: wSeg * 1.2, opacity: 0.5))
            var second = Path()
            second.move(to: m)
            second.addQuadCurve(
                to: b,
                control: CGPoint(x: (m.x + b.x) / 2, y: (m.y + b.y) / 2))
            strokes.append(InkStroke(path: second, width: wSeg * 0.8, opacity: 0.5))
            if i > 0 {
                // 节处顿笔：短粗 Q 钩（微弯，非直 L）
                var joint = Path()
                joint.move(to: a)
                joint.addQuadCurve(
                    to: CGPoint(x: a.x + ux * 3, y: a.y + uy * 3),
                    control: CGPoint(x: a.x + ux * 1.5 - uy * 1.2, y: a.y + uy * 1.5 + ux * 1.2))
                strokes.append(InkStroke(path: joint, width: w * 1.7, opacity: 0.55))
            }
        }
        return strokes
    }

    /// 细梢：中段两折点（真画梢多折、非直弧），叶生梢头。
    private static func twigInk(_ rnd: inout Mulberry32, _ tw: BambooTwigSpec) -> [InkStroke] {
        let m1 = CGPoint(
            x: tw.from.x + (tw.to.x - tw.from.x) * 0.38 + (rnd.next() - 0.5) * 7,
            y: tw.from.y + (tw.to.y - tw.from.y) * 0.38 + (rnd.next() - 0.5) * 7)
        let m2 = CGPoint(
            x: tw.from.x + (tw.to.x - tw.from.x) * 0.72 + (rnd.next() - 0.5) * 6,
            y: tw.from.y + (tw.to.y - tw.from.y) * 0.72 + (rnd.next() - 0.5) * 6)
        return branchInk(&rnd, [tw.from, m1, m2, tw.to], tw.w ?? 1.4)
    }
}

// MARK: - 竹拓纹理视图

/// 竹叶墨拓纹理：按布局逐笔绘制（基准坐标 × scale）。
struct BambooRubbing: View {
    let width: CGFloat
    let height: CGFloat
    var baseWidth: CGFloat = 70
    var baseHeight: CGFloat = 55
    var seed: UInt32 = 7211
    var layout: BambooLayoutSpec = .keepsakeCorner
    /// 整层不透明度（Figma 节点 opacity：Keepsake 0.68 / Namecard 0.72）。
    var layerOpacity: Double = 0.68

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            let s = min(width / baseWidth, height / baseHeight)
            ctx.scaleBy(x: s, y: s)
            ctx.opacity = layerOpacity
            let ink = CardInk.inkBlack
            for stroke in BambooInkBuilder.build(layout: layout, seed: seed) {
                let paint = GraphicsContext.Shading.color(ink.opacity(stroke.opacity))
                if stroke.fill {
                    ctx.fill(stroke.path, with: paint)
                } else if let dash = stroke.dash {
                    ctx.stroke(stroke.path, with: paint,
                               style: StrokeStyle(lineWidth: stroke.width, lineCap: .round,
                                                  dash: dash, dashPhase: stroke.dashPhase))
                } else {
                    ctx.stroke(stroke.path, with: paint,
                               style: StrokeStyle(lineWidth: stroke.width, lineCap: .round))
                }
            }
        }
    }
}
