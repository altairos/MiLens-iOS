import Foundation

// EditorDocument — 编辑器文档状态：管理图层列表、活动图层与层级操作。
// 翻译自源端 entry/.../editor/EditorDocument.ets（342 行）+ LayerSerializer.ets（221 行）。
//
// 架构差异：
// - 源端 Layer 接口分 ImageLayer/TextLayer，序列化含 PixelMap 恢复回调。
// - iOS 统一为 EditorLayer struct（Phase 1 已定义），无 PixelMap/sharpenBase 运行时资源。
//   序列化/反序列化纯用 JSONEncoder/JSONDecoder，不需要 pixelBackup/restorer 回调。

/// 序列化后的图层快照（不含运行时图像资源）。对应源端 `LayerSnapshotData`。
/// 字段名与源端保持一致以实现跨平台 JSON 兼容。
public struct EditorLayerSnapshot: Codable, Equatable {
    public var id: String
    public var type: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var scale: Double
    public var opacity: Double
    public var zIndex: Int
    public var flipX: Bool
    public var flipY: Bool
    // 调色参数（仅图片图层）
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var temperature: Double
    public var sharpness: Double
    // 文本字段（仅文字图层）
    public var text: String
    public var fontSize: Double
    public var fontColor: String
    public var maxWidth: Double
    public var strokeWidth: Double
    public var strokeColor: String
    // 照片底图是否含透明像素
    public var hasAlpha: Bool

    public init(id: String, type: String, x: Double, y: Double, width: Double, height: Double,
                rotation: Double, scale: Double, opacity: Double, zIndex: Int,
                flipX: Bool, flipY: Bool, brightness: Double, contrast: Double,
                saturation: Double, temperature: Double, sharpness: Double, text: String,
                fontSize: Double, fontColor: String, maxWidth: Double, strokeWidth: Double,
                strokeColor: String, hasAlpha: Bool) {
        self.id = id; self.type = type; self.x = x; self.y = y; self.width = width; self.height = height
        self.rotation = rotation; self.scale = scale; self.opacity = opacity; self.zIndex = zIndex
        self.flipX = flipX; self.flipY = flipY; self.brightness = brightness; self.contrast = contrast
        self.saturation = saturation; self.temperature = temperature; self.sharpness = sharpness
        self.text = text; self.fontSize = fontSize; self.fontColor = fontColor; self.maxWidth = maxWidth
        self.strokeWidth = strokeWidth; self.strokeColor = strokeColor; self.hasAlpha = hasAlpha
    }
}

// MARK: - 序列化辅助（对应源端 LayerSerializer.ets）

/// 把 EditorLayer 序列化为快照。对应源端 `serializeLayer`。
public func serializeEditorLayer(_ layer: EditorLayer) -> EditorLayerSnapshot {
    return EditorLayerSnapshot(
        id: layer.id, type: layer.type.rawValue,
        x: layer.x, y: layer.y, width: layer.width, height: layer.height,
        rotation: layer.rotation, scale: layer.scale, opacity: layer.opacity,
        zIndex: layer.zIndex, flipX: layer.flipX, flipY: layer.flipY,
        brightness: layer.adjustments.brightness, contrast: layer.adjustments.contrast,
        saturation: layer.adjustments.saturation, temperature: layer.adjustments.temperature,
        sharpness: layer.adjustments.sharpness,
        text: layer.text, fontSize: layer.fontSize, fontColor: layer.fontColor,
        maxWidth: layer.maxWidth, strokeWidth: layer.strokeWidth, strokeColor: layer.strokeColor,
        hasAlpha: layer.hasAlpha)
}

/// 把快照反序列化为 EditorLayer。对应源端 `deserializeLayer`。
/// iOS 简化：无需 PixelMap 恢复回调（App 层 ViewModel 单独管理图像资源）。
public func deserializeEditorLayer(_ data: EditorLayerSnapshot) -> EditorLayer {
    let layerType = EditorLayerType(rawValue: data.type) ?? .photo
    return EditorLayer(
        id: data.id, type: layerType, zIndex: data.zIndex, visible: true,
        x: data.x, y: data.y, scale: data.scale, rotation: data.rotation,
        opacity: data.opacity, flipX: data.flipX, flipY: data.flipY,
        width: data.width > 0 ? data.width : 100,
        height: data.height > 0 ? data.height : 100,
        hasAlpha: data.hasAlpha,
        adjustments: EditorColorAdjustments(
            brightness: data.brightness, contrast: data.contrast,
            saturation: data.saturation, temperature: data.temperature,
            sharpness: data.sharpness),
        text: data.text, fontSize: data.fontSize > 0 ? data.fontSize : 32,
        fontColor: data.fontColor.isEmpty ? "#FFFFFF" : data.fontColor,
        strokeWidth: data.strokeWidth > 0 ? data.strokeWidth : 2,
        strokeColor: data.strokeColor.isEmpty ? "#000000" : data.strokeColor,
        maxWidth: data.maxWidth > 0 ? data.maxWidth : 400)
}

// MARK: - EditorDocument

/// 编辑器文档状态。对应源端 `EditorDocument`（342 行）。
/// 管理图层列表、活动图层与层级操作。不持有运行时图像资源。
public final class EditorDocument {

    private(set) var layers: [EditorLayer] = []
    private var activeLayerId: String? = nil

    public init() {}

    // MARK: - 查询

    /// 当前图层数量。
    public var layerCount: Int { layers.count }

    /// 当前活动图层。
    public var activeLayer: EditorLayer? {
        guard let activeLayerId else { return nil }
        return layers.first { $0.id == activeLayerId }
    }

    /// 是否存在活动图层。
    public func hasActiveLayer() -> Bool { activeLayer != nil }

    /// 获取图层副本。
    public func getLayers() -> [EditorLayer] { layers }

    /// 按 id 查找图层。
    public func findLayer(_ id: String) -> EditorLayer? {
        layers.first { $0.id == id }
    }

    // MARK: - 增删

    /// 添加图层并自动分配 zIndex。
    /// - Parameter makeActive: 是否设为活动图层，默认 true。
    public func add(_ layer: inout EditorLayer, makeActive: Bool = true) {
        layer.zIndex = layers.count
        layers.append(layer)
        if makeActive { activeLayerId = layer.id }
    }

    /// 添加图层但不改变活动图层（用于初始加载底图）。
    public func addPassive(_ layer: inout EditorLayer) {
        layer.zIndex = layers.count
        layers.append(layer)
        if activeLayerId == nil { activeLayerId = layer.id }
    }

    /// 移除指定图层并重排 zIndex；若移除活动图层则回退到末尾。
    @discardableResult
    public func remove(_ id: String) -> Bool {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return false }
        layers.remove(at: idx)
        reindex()
        if activeLayerId == id {
            activeLayerId = layers.last?.id
        }
        return true
    }

    /// 设置活动图层。
    public func select(_ id: String?) {
        guard let id else { activeLayerId = nil; return }
        if layers.contains(where: { $0.id == id }) { activeLayerId = id }
    }

    /// 就地更新图层属性（按 id 替换副本，保持 zIndex/顺序不变）。
    /// 对应源端 LayerManager 的图层属性更新语义（updateText/moveLayer 等）。
    /// - Returns: 更新成功 true（图层存在时）。
    @discardableResult
    public func updateLayer(_ id: String, _ transform: (inout EditorLayer) -> Void) -> Bool {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return false }
        var updated = layers[idx]
        transform(&updated)
        layers[idx] = updated
        return true
    }

    // MARK: - 层级操作

    /// 向上移一层。
    @discardableResult
    public func bringForward(_ id: String) -> Bool { moveBy(id, delta: 1) }

    /// 向下移一层。
    @discardableResult
    public func sendBackward(_ id: String) -> Bool { moveBy(id, delta: -1) }

    /// 移到最顶层。
    @discardableResult
    public func bringToFront(_ id: String) -> Bool {
        guard findLayer(id) != nil else { return false }
        var sorted = sortedByZ()
        guard let idx = sorted.firstIndex(where: { $0.id == id }), idx != sorted.count - 1 else { return false }
        reorderFrom(&sorted, id: id, targetIdx: sorted.count - 1)
        return true
    }

    /// 移到最底层。
    @discardableResult
    public func sendToBack(_ id: String) -> Bool {
        guard findLayer(id) != nil else { return false }
        var sorted = sortedByZ()
        guard let idx = sorted.firstIndex(where: { $0.id == id }), idx > 0 else { return false }
        reorderFrom(&sorted, id: id, targetIdx: 0)
        return true
    }

    // MARK: - 序列化

    /// 序列化所有图层为 JSON 字符串。
    public func serialize() -> String? {
        let snapshots = layers.map { serializeEditorLayer($0) }
        let encoder = JSONEncoder()
        return try? encoder.encode(snapshots).asString()
    }

    /// 从 JSON 字符串恢复图层元数据。
    /// - Returns: 恢复成功 true；JSON 解析失败 false。
    @discardableResult
    public func restore(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        let decoder = JSONDecoder()
        guard let snapshots = try? decoder.decode([EditorLayerSnapshot].self, from: data) else { return false }
        layers = snapshots.map { deserializeEditorLayer($0) }
        if let active = activeLayerId, !layers.contains(where: { $0.id == active }) {
            activeLayerId = layers.last?.id
        }
        return true
    }

    /// 创建空文档。
    public static func createEmpty() -> EditorDocument { EditorDocument() }

    // MARK: - 内部辅助

    private func reindex() {
        for i in layers.indices { layers[i].zIndex = i }
    }

    private func sortedByZ() -> [EditorLayer] {
        layers.sorted { $0.zIndex < $1.zIndex }
    }

    /// 在按 zIndex 升序排列的副本上，把目标图层移到目标位置。
    private func reorderFrom(_ sorted: inout [EditorLayer], id: String, targetIdx: Int) {
        guard let fromIdx = sorted.firstIndex(where: { $0.id == id }) else { return }
        let removed = sorted.remove(at: fromIdx)
        sorted.insert(removed, at: min(targetIdx, sorted.count))
        for i in sorted.indices { sorted[i].zIndex = i }
        layers = sorted
    }

    private func moveBy(_ id: String, delta: Int) -> Bool {
        guard findLayer(id) != nil else { return false }
        var sorted = sortedByZ()
        guard let idx = sorted.firstIndex(where: { $0.id == id }) else { return false }
        let target = idx + delta
        guard target >= 0, target < sorted.count, target != idx else { return false }
        sorted.swapAt(idx, target)
        for i in sorted.indices { sorted[i].zIndex = i }
        layers = sorted
        return true
    }
}

// MARK: - Data 扩展

private extension Data {
    func asString() -> String { String(data: self, encoding: .utf8) ?? "" }
}
