//  RedPacketCoverRenderer —— 红包封面单一渲染器（对应红包封面开发计划 §6.3）。
//
//  编辑画布与最终导出共用此渲染器（不两套排版逻辑）。
//  渲染顺序固定：背景层 → 宠物抠图层 → 配饰/文本层 → 前景层。
//  程序化绘制背景（按 RedPacketBackgroundDescriptor：渐变/纯色/装饰）。

import SwiftUI
import UIKit
import MiLensKit

/// 红包封面渲染器。编辑画布与导出共用。
struct RedPacketCoverRenderer: View {
    let template: RedPacketTemplate
    let layers: [RedPacketLayer]
    let petImage: UIImage?
    let includeWatermark: Bool
    var showSafeZone: Bool = false

    init(
        template: RedPacketTemplate,
        layers: [RedPacketLayer],
        petImage: UIImage? = nil,
        includeWatermark: Bool = false,
        showSafeZone: Bool = false
    ) {
        self.template = template
        self.layers = layers
        self.petImage = petImage
        self.includeWatermark = includeWatermark
        self.showSafeZone = showSafeZone
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // 1. 背景层
                backgroundView(template.background, size: geo.size)

                // 2. 宠物抠图层
                if let petLayer = layers.first(where: { $0.kind == .pet && $0.visible }),
                   let petImage {
                    Image(uiImage: petImage)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: petLayer.width * petLayer.scale * (w / rpCanvasWidth),
                            height: petLayer.height * petLayer.scale * (w / rpCanvasWidth)
                        )
                        .opacity(petLayer.opacity)
                        .rotationEffect(.degrees(petLayer.rotation))
                        .position(
                            x: petLayer.x * (w / rpCanvasWidth),
                            y: petLayer.y * (h / rpCanvasHeight)
                        )
                }

                // 3. 配饰与文本层（按 zIndex 排序）
                ForEach(userContentLayers) { layer in
                    if layer.visible {
                        layerView(layer, canvasW: w, canvasH: h)
                    }
                }

                // 4. 前景层
                if let foreground = template.foreground {
                    foregroundView(foreground, size: geo.size)
                }

                // 安全区遮罩（编辑提示，不参与导出）
                if showSafeZone {
                    safeZoneOverlay(size: geo.size)
                }

                // 水印
                if includeWatermark {
                    Text("MiLens")
                        .font(.system(size: w * 0.025, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.trailing, w * 0.06)
                        .padding(.top, h * 0.42)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
        .aspectRatio(
            rpCanvasWidth / rpCanvasHeight,
            contentMode: .fit
        )
    }

    // MARK: - 用户内容层

    private var userContentLayers: [RedPacketLayer] {
        layers
            .filter { $0.kind == .accessory || $0.kind == .text }
            .sorted { $0.zIndex < $1.zIndex }
    }

    // MARK: - 层渲染

    @ViewBuilder
    private func layerView(_ layer: RedPacketLayer, canvasW: Double, canvasH: Double) -> some View {
        let scaleX = canvasW / rpCanvasWidth
        let scaleY = canvasH / rpCanvasHeight
        switch layer.kind {
        case .text:
            textView(layer, scaleX: scaleX, scaleY: scaleY)
        case .accessory:
            accessoryView(layer, scaleX: scaleX, scaleY: scaleY)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func accessoryView(_ layer: RedPacketLayer, scaleX: Double, scaleY: Double) -> some View {
        // Phase 2：配饰用 emoji 渲染（resourceRef 映射 emoji）
        let emoji = RedPacketAccessoryEmoji.emoji(for: layer.resourceRef)
        Text(emoji)
            .font(.system(size: min(layer.width, layer.height) * scaleX * CGFloat(layer.scale)))
            .rotationEffect(.degrees(layer.rotation))
            .opacity(layer.opacity)
            .position(x: layer.x * scaleX, y: layer.y * scaleY)
    }

    @ViewBuilder
    private func textView(_ layer: RedPacketLayer, scaleX: Double, scaleY: Double) -> some View {
        let style = RedPacketTextStylePreset(rawValue: layer.styleID)?.style
            ?? RedPacketTextStylePreset.festive.style
        let fontSize = style.fontSizeRatio * rpCanvasWidth * scaleX
        Text(layer.text)
            .font(.custom(style.fontFamily, size: fontSize))
            .foregroundStyle(Color(hex: style.colorHex))
            .multilineTextAlignment(textAlignment(style.alignment))
            .rotationEffect(.degrees(layer.rotation))
            .opacity(layer.opacity)
            .frame(width: layer.width * scaleX, height: layer.height * scaleY)
            .position(x: layer.x * scaleX, y: layer.y * scaleY)
    }

    // MARK: - 背景

    @ViewBuilder
    private func backgroundView(_ descriptor: RedPacketBackgroundDescriptor, size: CGSize) -> some View {
        switch descriptor {
        case .solid(let hex):
            Color(hex: hex)
        case .gradient(let colors, let angle):
            LinearGradient(
                colors: colors.map { Color(hex: $0) },
                startPoint: gradientStart(angle: angle),
                endPoint: gradientEnd(angle: angle)
            )
        case .decorated(let base, let pattern, let patternColorHex):
            ZStack {
                LinearGradient(
                    colors: base.colors.map { Color(hex: $0) },
                    startPoint: gradientStart(angle: base.angle),
                    endPoint: gradientEnd(angle: base.angle)
                )
                decorativePattern(pattern, colorHex: patternColorHex, size: size)
            }
        case .resource:
            // Phase 0 不使用资源背景
            Color.gray.opacity(0.3)
        }
    }

    @ViewBuilder
    private func foregroundView(_ descriptor: RedPacketBackgroundDescriptor, size: CGSize) -> some View {
        switch descriptor {
        case .solid(let hex):
            Color(hex: hex)
        case .gradient(let colors, let angle):
            LinearGradient(
                colors: colors.map { Color(hex: $0) },
                startPoint: gradientStart(angle: angle),
                endPoint: gradientEnd(angle: angle)
            )
        case .decorated(let base, _, _):
            LinearGradient(
                colors: base.colors.map { Color(hex: $0) },
                startPoint: gradientStart(angle: base.angle),
                endPoint: gradientEnd(angle: base.angle)
            )
        case .resource:
            Color.clear
        }
    }

    // MARK: - 装饰图案

    @ViewBuilder
    private func decorativePattern(_ pattern: String, colorHex: String, size: CGSize) -> some View {
        let patternColor = Color(hex: colorHex).opacity(0.15)
        switch pattern {
        case "circles":
            // 圆形装饰图案
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .stroke(patternColor, lineWidth: 2)
                        .frame(width: size.width * CGFloat(0.15 + Double(i) * 0.1))
                        .position(
                            x: size.width * CGFloat(0.2 + Double(i % 3) * 0.3),
                            y: size.height * CGFloat(0.3 + Double(i % 2) * 0.4)
                        )
                }
            }
        case "dots":
            // 点状图案
            ZStack {
                ForEach(0..<20, id: \.self) { i in
                    Circle()
                        .fill(patternColor)
                        .frame(width: 8, height: 8)
                        .position(
                            x: size.width * CGFloat(0.05 + Double(i % 5) * 0.22),
                            y: size.height * CGFloat(0.05 + Double(i / 5) * 0.22)
                        )
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - 安全区遮罩

    private func safeZoneOverlay(size: CGSize) -> some View {
        let zone = template.safeZone
        return ZStack {
            // 风险区（红色半透明）
            Rectangle()
                .fill(Color.red.opacity(0.1))
                .frame(
                    width: size.width * CGFloat(template.riskZone.width),
                    height: size.height * CGFloat(template.riskZone.height)
                )
                .position(
                    x: size.width * CGFloat(template.riskZone.x + template.riskZone.width / 2),
                    y: size.height * CGFloat(template.riskZone.y + template.riskZone.height / 2)
                )
            // 安全区边框
            Rectangle()
                .stroke(Color.white.opacity(0.4), style: StrokeStyle(
                    lineWidth: 1, dash: [4, 4]
                ))
                .frame(
                    width: size.width * CGFloat(zone.width),
                    height: size.height * CGFloat(zone.height)
                )
                .position(
                    x: size.width * CGFloat(zone.x + zone.width / 2),
                    y: size.height * CGFloat(zone.y + zone.height / 2)
                )
        }
    }

    // MARK: - 工具

    private func gradientStart(angle: Double) -> UnitPoint {
        if angle <= 45 { return .top }
        if angle <= 135 { return .leading }
        if angle <= 225 { return .bottom }
        return .trailing
    }

    private func gradientEnd(angle: Double) -> UnitPoint {
        if angle <= 45 { return .bottom }
        if angle <= 135 { return .trailing }
        if angle <= 225 { return .top }
        return .leading
    }

    private func textAlignment(_ alignment: RedPacketTextAlignment) -> TextAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Color Hex 扩展

/// 十六进制颜色字符串转 SwiftUI Color。
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 8: // RGBA
            (r, g, b, a) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 6: // RGB
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, 255)
        case 3: // RGB (shorthand)
            (r, g, b, a) = (
                (int >> 8 & 0xF) * 17,
                (int >> 4 & 0xF) * 17,
                (int & 0xF) * 17,
                255
            )
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - 配饰 Emoji 映射

/// 配饰 resourceRef 到 emoji 的映射（Phase 2 程序化占位）。
enum RedPacketAccessoryEmoji {
    static func emoji(for resourceRef: String) -> String {
        switch resourceRef {
        case "acc_lantern":     return "🏮"
        case "acc_firecracker": return "🧨"
        case "acc_coin":        return "🪙"
        case "acc_flower":      return "🌸"
        case "acc_paw":         return "🐾"
        case "acc_heart":       return "❤️"
        case "acc_star":        return "⭐"
        case "acc_bow":         return "🎀"
        default:                return "✨"
        }
    }
}
