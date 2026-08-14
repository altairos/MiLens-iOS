import Foundation

// RedPacketLayoutLogic — 红包封面布局纯函数（对应红包封面开发计划 §3.2）。
//
// 借鉴 EditorLayerGeometry 的几何语义（hitTest/旋转反变换/clamp），但独立实现于红包模型。
// 输入只读 RedPacketLayer / RedPacketTemplate 字段，不修改对象状态。
// 所有坐标使用 957×1278 设计画布坐标系。

// MARK: - 常量

/// 红包图层缩放范围。
public let RP_MIN_LAYER_SCALE: Double = 0.2
public let RP_MAX_LAYER_SCALE: Double = 5.0

/// 红包画布尺寸常量。
public var rpCanvasWidth: Double { Double(WeChatRedPacketSpec.coverImageWidth) }
public var rpCanvasHeight: Double { Double(WeChatRedPacketSpec.coverImageHeight) }

// MARK: - 几何数据结构

/// 红包图层半宽/半高（已乘 scale）。
public struct RedPacketLayerHalfSize: Equatable, Sendable {
    public var halfW: Double
    public var halfH: Double
    public init(halfW: Double, halfH: Double) {
        self.halfW = halfW
        self.halfH = halfH
    }
}

/// 图层本地坐标（旋转反变换后）。
public struct RedPacketLocalPoint: Equatable, Sendable {
    public var localX: Double
    public var localY: Double
    public init(localX: Double, localY: Double) {
        self.localX = localX
        self.localY = localY
    }
}

/// 图层旋转后的轴对齐外接框（画布坐标）。
public struct RedPacketLayerBounds: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { max(0, maxX - minX) }
    public var height: Double { max(0, maxY - minY) }
    public var area: Double { width * height }
}

// MARK: - 缩放/位置约束

/// 把 scale clamp 到 [RP_MIN_LAYER_SCALE, RP_MAX_LAYER_SCALE]。
public func rpClampScale(_ scale: Double) -> Double {
    if !scale.isFinite { return RP_MIN_LAYER_SCALE }
    return max(RP_MIN_LAYER_SCALE, min(RP_MAX_LAYER_SCALE, scale))
}

/// 把图层中心点约束到画布范围内（允许半个图层出界，但中心不出界）。
public func rpClampPosition(x: Double, y: Double) -> (x: Double, y: Double) {
    let cx = rpCanvasWidth
    let cy = rpCanvasHeight
    let clampedX = x.isFinite ? max(0, min(cx, x)) : cx / 2
    let clampedY = y.isFinite ? max(0, min(cy, y)) : cy / 2
    return (clampedX, clampedY)
}

/// 抠图主体初始入画尺寸：在模板安全区内等比缩放，长边占安全区对应边的 82%，
/// 保证主体足够突出又不贴边。非法像素尺寸返回 nil（调用方保留图层原状）。
public func rpFitCutoutLayerSize(
    pixelWidth: Int,
    pixelHeight: Int,
    template: RedPacketTemplate
) -> (width: Double, height: Double)? {
    guard pixelWidth > 0, pixelHeight > 0 else { return nil }
    let zone = template.safeZone
    let maxWidth = zone.width * rpCanvasWidth * 0.82
    let maxHeight = zone.height * rpCanvasHeight * 0.82
    let fitScale = min(
        maxWidth / Double(pixelWidth),
        maxHeight / Double(pixelHeight)
    )
    return (Double(pixelWidth) * fitScale, Double(pixelHeight) * fitScale)
}

// MARK: - 几何计算

/// 计算图层的半宽/半高（已乘 scale）。
public func rpComputeLayerHalfSize(_ layer: RedPacketLayer) -> RedPacketLayerHalfSize {
    let w = layer.width.isFinite && layer.width > 0 ? layer.width : 100
    let h = layer.height.isFinite && layer.height > 0 ? layer.height : 100
    let safeScale = layer.scale.isFinite && layer.scale > 0 ? layer.scale : 1
    return RedPacketLayerHalfSize(halfW: w * safeScale / 2, halfH: h * safeScale / 2)
}

/// 把画布坐标反变换到图层本地坐标（旋转反变换）。
public func rpRotatePointToLocal(
    layerX: Double, layerY: Double, rotationDeg: Double,
    tapX: Double, tapY: Double
) -> RedPacketLocalPoint {
    let safeRotation = rotationDeg.isFinite ? rotationDeg : 0
    let rad = -safeRotation * .pi / 180
    let dx = tapX - layerX
    let dy = tapY - layerY
    let cosR = cos(rad)
    let sinR = sin(rad)
    return RedPacketLocalPoint(
        localX: dx * cosR - dy * sinR,
        localY: dx * sinR + dy * cosR
    )
}

/// 判断画布点是否落在图层边界内。
public func rpIsPointInLayer(_ layer: RedPacketLayer, tapX: Double, tapY: Double) -> Bool {
    if !layer.visible || layer.kind.isTemplateFixed { return false }
    let half = rpComputeLayerHalfSize(layer)
    if half.halfW <= 0 || half.halfH <= 0 { return false }
    let local = rpRotatePointToLocal(
        layerX: layer.x, layerY: layer.y,
        rotationDeg: layer.rotation, tapX: tapX, tapY: tapY
    )
    return abs(local.localX) <= half.halfW && abs(local.localY) <= half.halfH
}

/// 计算图层旋转后的轴对齐外接框。
public func rpLayerBounds(_ layer: RedPacketLayer) -> RedPacketLayerBounds {
    let half = rpComputeLayerHalfSize(layer)
    let radians = (layer.rotation.isFinite ? layer.rotation : 0) * .pi / 180
    let cosValue = abs(cos(radians))
    let sinValue = abs(sin(radians))
    let rotatedHalfWidth = half.halfW * cosValue + half.halfH * sinValue
    let rotatedHalfHeight = half.halfW * sinValue + half.halfH * cosValue
    return RedPacketLayerBounds(
        minX: layer.x - rotatedHalfWidth,
        minY: layer.y - rotatedHalfHeight,
        maxX: layer.x + rotatedHalfWidth,
        maxY: layer.y + rotatedHalfHeight
    )
}

/// 图层旋转外接框仍位于导出画布内的比例。
public func rpLayerCanvasVisibleRatio(_ layer: RedPacketLayer) -> Double {
    let canvas = RedPacketLayerBounds(
        minX: 0, minY: 0, maxX: rpCanvasWidth, maxY: rpCanvasHeight
    )
    return rpIntersectionRatio(bounds: rpLayerBounds(layer), container: canvas)
}

/// 图层旋转外接框位于模板安全区内的比例。
public func rpLayerSafeZoneCoverageRatio(
    _ layer: RedPacketLayer, template: RedPacketTemplate
) -> Double {
    let zone = template.safeZone
    let safeBounds = RedPacketLayerBounds(
        minX: zone.x * rpCanvasWidth,
        minY: zone.y * rpCanvasHeight,
        maxX: (zone.x + zone.width) * rpCanvasWidth,
        maxY: (zone.y + zone.height) * rpCanvasHeight
    )
    return rpIntersectionRatio(bounds: rpLayerBounds(layer), container: safeBounds)
}

private func rpIntersectionRatio(
    bounds: RedPacketLayerBounds, container: RedPacketLayerBounds
) -> Double {
    guard bounds.area > 0 else { return 0 }
    let intersectionWidth = max(0, min(bounds.maxX, container.maxX) - max(bounds.minX, container.minX))
    let intersectionHeight = max(0, min(bounds.maxY, container.maxY) - max(bounds.minY, container.minY))
    let ratio = intersectionWidth * intersectionHeight / bounds.area
    return max(0, min(1, ratio.isFinite ? ratio : 0))
}

// MARK: - 命中测试

/// 自顶向下找到首个被点击的用户可编辑图层，返回其 ID（nil = 点击空白）。
public func rpHitTest(
    layers: [RedPacketLayer], canvasX: Double, canvasY: Double
) -> String? {
    // 按 zIndex 降序（顶层优先）
    let sorted = layers
        .filter { $0.kind.isUserEditable && $0.visible }
        .sorted { $0.zIndex > $1.zIndex }
    for layer in sorted {
        if rpIsPointInLayer(layer, tapX: canvasX, tapY: canvasY) {
            return layer.id
        }
    }
    return nil
}

// MARK: - 默认图层生成

/// 为模板生成默认图层集合（背景 + 前景 + 默认隐藏 pet 占位 + 默认文本）。
public func rpDefaultLayers(for template: RedPacketTemplate, petName: String = "") -> [RedPacketLayer] {
    var layers: [RedPacketLayer] = []

    // 1. 背景层
    var bg = makeRedPacketTemplateBackgroundLayer()
    bg.resourceRef = template.id
    layers.append(bg)

    // 2. pet 占位层（默认隐藏，加载抠图后显示并更新尺寸）
    let petTransform = template.defaultPetTransform
    let petLayer = makeRedPacketPetLayer(
        x: petTransform.x, y: petTransform.y,
        scale: petTransform.scale,
        width: rpCanvasWidth * 0.5, height: rpCanvasHeight * 0.35
    )
    var mutablePet = petLayer
    mutablePet.rotation = petTransform.rotation
    mutablePet.visible = false
    layers.append(mutablePet)

    // 3. 默认文本层
    let textTransform = template.defaultTextPosition
    let textContent = petName.isEmpty ? "恭喜发财" : petName
    let textLayer = makeRedPacketTextLayer(
        text: textContent,
        x: textTransform.x, y: textTransform.y,
        stylePreset: template.defaultTextStylePreset,
        width: rpCanvasWidth * 0.5, height: rpCanvasHeight * 0.05
    )
    layers.append(textLayer)

    // 4. 前景层
    if template.foreground != nil {
        var fg = makeRedPacketTemplateForegroundLayer()
        fg.resourceRef = template.id + "_fg"
        layers.append(fg)
    }

    return layers
}

// MARK: - 模板切换（保留内容策略）

/// 切换模板：保留 pet 资源/抠图、文本内容和配饰；重算背景/前景/默认排版。
/// 对应红包封面开发计划 §2.1「切换模板时保留照片、抠图结果和文本内容」。
public func rpSwitchTemplate(
    oldLayers: [RedPacketLayer], newTemplate: RedPacketTemplate
) -> [RedPacketLayer] {
    // 找到旧图层中的用户内容
    let oldPet = oldLayers.first { $0.kind == .pet }
    let oldText = oldLayers.first { $0.kind == .text }
    let oldAccessories = oldLayers.filter { $0.kind == .accessory }

    // 生成新模板默认图层
    var newLayers = rpDefaultLayers(for: newTemplate, petName: oldText?.text ?? "")

    // 保留 pet 图层（位置用新模板默认值，但保留资源/尺寸/抠图）
    if let oldPet, let petIdx = newLayers.firstIndex(where: { $0.kind == .pet }) {
        let newTransform = newTemplate.defaultPetTransform
        var preserved = oldPet
        preserved.x = newTransform.x
        preserved.y = newTransform.y
        newLayers[petIdx] = preserved
    }

    // 保留文本内容（用新模板的默认风格和位置）
    if let oldText, let textIdx = newLayers.firstIndex(where: { $0.kind == .text }) {
        var preserved = newLayers[textIdx]
        preserved.text = oldText.text
        preserved.styleID = newTemplate.defaultTextStylePreset.rawValue
        let textPos = newTemplate.defaultTextPosition
        preserved.x = textPos.x
        preserved.y = textPos.y
        newLayers[textIdx] = preserved
    }

    // 保留配饰（zIndex 保持不变，直接追加）
    newLayers.append(contentsOf: oldAccessories)

    return newLayers
}

// MARK: - 照片替换

/// 替换宠物照片图层（保留模板/文本/配饰，更新 pet 层）。
/// 对应红包封面开发计划 §2.2「换照片时默认保留模板、文本内容和配饰」。
public func rpReplacePhoto(
    layers: [RedPacketLayer], newPetLayer: RedPacketLayer
) -> [RedPacketLayer] {
    var result = layers
    if let idx = result.firstIndex(where: { $0.kind == .pet }) {
        result[idx] = newPetLayer
    } else {
        result.append(newPetLayer)
    }
    return result
}

// MARK: - 安全区判定

/// 判断图层中心是否在模板安全区内。
public func rpIsLayerInSafeZone(
    _ layer: RedPacketLayer, template: RedPacketTemplate
) -> Bool {
    let zone = template.safeZone
    let zoneMinX = zone.x * rpCanvasWidth
    let zoneMaxX = (zone.x + zone.width) * rpCanvasWidth
    let zoneMinY = zone.y * rpCanvasHeight
    let zoneMaxY = (zone.y + zone.height) * rpCanvasHeight
    return layer.x >= zoneMinX && layer.x <= zoneMaxX &&
           layer.y >= zoneMinY && layer.y <= zoneMaxY
}

// MARK: - 图层操作

/// 把活动图层居中到画布中心。
public func rpCenterLayer(_ layer: RedPacketLayer) -> RedPacketLayer {
    var result = layer
    result.x = rpCanvasWidth / 2
    result.y = rpCanvasHeight / 2
    return result
}

/// 把活动图层恢复到模板默认位置。
public func rpResetLayerToDefault(
    _ layer: RedPacketLayer, template: RedPacketTemplate
) -> RedPacketLayer {
    var result = layer
    switch layer.kind {
    case .pet:
        result.x = template.defaultPetTransform.x
        result.y = template.defaultPetTransform.y
        result.scale = template.defaultPetTransform.scale
        result.rotation = template.defaultPetTransform.rotation
    case .text:
        result.x = template.defaultTextPosition.x
        result.y = template.defaultTextPosition.y
        result.scale = 1.0
        result.rotation = 0
    default:
        break
    }
    return result
}

/// 删除指定图层（模板固定层不可删除）。
public func rpDeleteLayer(_ layers: [RedPacketLayer], id: String) -> [RedPacketLayer] {
    layers.filter { !($0.id == id && $0.kind.isUserEditable) }
}

/// 更新指定图层。
public func rpUpdateLayer(
    _ layers: [RedPacketLayer], id: String,
    update: (inout RedPacketLayer) -> Void
) -> [RedPacketLayer] {
    layers.map { layer in
        guard layer.id == id else { return layer }
        var copy = layer
        update(&copy)
        return copy
    }
}
