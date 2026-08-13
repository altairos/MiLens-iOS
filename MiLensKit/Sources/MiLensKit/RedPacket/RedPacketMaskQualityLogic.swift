import Foundation

/// 从主体分割 alpha 蒙版提取的质量指标。数值均归一化到 0...1。
public struct RedPacketMaskMetrics: Equatable, Sendable {
    public var foregroundRatio: Double
    public var edgeRoughness: Double
    public var fragmentationRatio: Double
    public var boundaryTouchRatio: Double

    public init(
        foregroundRatio: Double = 0,
        edgeRoughness: Double = 0,
        fragmentationRatio: Double = 0,
        boundaryTouchRatio: Double = 0
    ) {
        self.foregroundRatio = foregroundRatio
        self.edgeRoughness = edgeRoughness
        self.fragmentationRatio = fragmentationRatio
        self.boundaryTouchRatio = boundaryTouchRatio
    }
}

/// 主体分割蒙版的轻量、本地质量分析。
public enum RedPacketMaskQualityLogic {
    private static let foregroundThreshold: UInt8 = 128
    private static let maxSampleDimension = 256

    /// 分析 8-bit alpha 蒙版。数据不完整时返回 nil，避免把失败误报为“质量良好”。
    public static func analyze(mask: Data, width: Int, height: Int) -> RedPacketMaskMetrics? {
        guard width > 0, height > 0, mask.count >= width * height else { return nil }

        let step = max(1, Int(ceil(Double(max(width, height)) / Double(maxSampleDimension))))
        let sampleWidth = Int(ceil(Double(width) / Double(step)))
        let sampleHeight = Int(ceil(Double(height) / Double(step)))
        var foreground = [Bool](repeating: false, count: sampleWidth * sampleHeight)

        mask.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for sampleY in 0..<sampleHeight {
                let sourceY = min(sampleY * step, height - 1)
                for sampleX in 0..<sampleWidth {
                    let sourceX = min(sampleX * step, width - 1)
                    foreground[sampleY * sampleWidth + sampleX] =
                        bytes[sourceY * width + sourceX] >= foregroundThreshold
                }
            }
        }

        let foregroundCount = foreground.reduce(into: 0) { count, value in
            if value { count += 1 }
        }
        guard foregroundCount > 0 else {
            return RedPacketMaskMetrics()
        }

        let total = sampleWidth * sampleHeight
        let foregroundRatio = Double(foregroundCount) / Double(max(total, 1))
        let largestComponent = largestConnectedComponent(
            foreground, width: sampleWidth, height: sampleHeight
        )
        let fragmentation = 1 - Double(largestComponent) / Double(foregroundCount)
        let boundaryTouch = boundaryTouchRatio(
            foreground, width: sampleWidth, height: sampleHeight
        )
        let roughness = edgeRoughness(
            foreground, width: sampleWidth, height: sampleHeight,
            foregroundCount: foregroundCount
        )

        return RedPacketMaskMetrics(
            foregroundRatio: clamp01(foregroundRatio),
            edgeRoughness: clamp01(roughness),
            fragmentationRatio: clamp01(fragmentation),
            boundaryTouchRatio: clamp01(boundaryTouch)
        )
    }

    private static func largestConnectedComponent(
        _ foreground: [Bool], width: Int, height: Int
    ) -> Int {
        var visited = [Bool](repeating: false, count: foreground.count)
        var largest = 0
        var queue: [Int] = []
        queue.reserveCapacity(foreground.count)

        for start in foreground.indices where foreground[start] && !visited[start] {
            visited[start] = true
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            var cursor = 0

            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                let x = index % width
                let y = index / width

                if x > 0 { enqueue(index - 1, foreground: foreground, visited: &visited, queue: &queue) }
                if x + 1 < width { enqueue(index + 1, foreground: foreground, visited: &visited, queue: &queue) }
                if y > 0 { enqueue(index - width, foreground: foreground, visited: &visited, queue: &queue) }
                if y + 1 < height { enqueue(index + width, foreground: foreground, visited: &visited, queue: &queue) }
            }
            largest = max(largest, queue.count)
        }
        return largest
    }

    private static func enqueue(
        _ index: Int,
        foreground: [Bool],
        visited: inout [Bool],
        queue: inout [Int]
    ) {
        guard foreground[index], !visited[index] else { return }
        visited[index] = true
        queue.append(index)
    }

    private static func boundaryTouchRatio(
        _ foreground: [Bool], width: Int, height: Int
    ) -> Double {
        guard width > 0, height > 0 else { return 0 }
        var touched = 0
        var boundaryCount = 0
        for y in 0..<height {
            for x in 0..<width where x == 0 || y == 0 || x == width - 1 || y == height - 1 {
                boundaryCount += 1
                if foreground[y * width + x] { touched += 1 }
            }
        }
        return Double(touched) / Double(max(boundaryCount, 1))
    }

    /// 以离散周长相对同面积圆的超额比例衡量毛刺，兼顾不同尺寸蒙版。
    private static func edgeRoughness(
        _ foreground: [Bool], width: Int, height: Int, foregroundCount: Int
    ) -> Double {
        var perimeter = 0
        for y in 0..<height {
            for x in 0..<width where foreground[y * width + x] {
                if x == 0 || !foreground[y * width + x - 1] { perimeter += 1 }
                if x == width - 1 || !foreground[y * width + x + 1] { perimeter += 1 }
                if y == 0 || !foreground[(y - 1) * width + x] { perimeter += 1 }
                if y == height - 1 || !foreground[(y + 1) * width + x] { perimeter += 1 }
            }
        }
        let minimumPerimeter = 2 * sqrt(.pi * Double(foregroundCount))
        guard minimumPerimeter > 0 else { return 0 }
        return max(0, Double(perimeter) / minimumPerimeter - 1) / 4
    }

    private static func clamp01(_ value: Double) -> Double {
        max(0, min(1, value.isFinite ? value : 0))
    }
}
