import Foundation

// BeadPixelBuffer — RGBA↔BGRA 通道交换。
// 逐行翻译自源端 shared/.../bead/BeadPixelBuffer.ets（11 行）。

/// 原地交换 RGBA buffer 的红蓝通道（用于创建输出 PixelMap 时的字节序适配）。
/// 对应源端 `swapRedBlueChannelsInPlace`。
public func swapRedBlueChannelsInPlace(_ buffer: inout [UInt8]) {
    var i = 0
    while i + 3 < buffer.count {
        let red = buffer[i]
        buffer[i] = buffer[i + 2]
        buffer[i + 2] = red
        i += 4
    }
}
