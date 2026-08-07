//  扫描/导入用例层类型与常量（对应源端 services/PhotoScanner.ets 类型 + constants/AppConstants.ets）。
//  DESIGN.md §4：Service 编排 IO + 异常处理 + 文案决策。

import Foundation

/// 扫描进度回调数据（对应源端 ScanProgress）
struct ScanProgress: Sendable {
    let scanned: Int
    let total: Int
    let petPhotosFound: Int
    let matchedCount: Int
    let currentIdentifier: String
}

/// 导入进度回调数据
struct ImportProgress: Sendable {
    let current: Int
    let total: Int
}

/// 扫描/导入管线常量（对应源端 SCAN_CONSTANTS / AI_CONSTANTS / THUMB_CONSTANTS）
enum ScanConfig {
    /// 沙盒照片子目录名（对应源端 filesDir/MiPhotos）
    static let sandboxDirName = "MiPhotos"
    /// AI 检测输入尺寸（像素，对应源端 AI_CONSTANTS.DETECT_INPUT_SIZE）
    static let detectInputSize = 256
    /// 沙盒副本最大边长（对应源端缩放到 1024px JPEG）
    static let importMaxDimension = 1024
    /// 每处理多少张后冷却（对应源端 SCAN_CONSTANTS.COOLDOWN_BATCH_SIZE）
    static let cooldownBatchSize = 50
    /// 冷却时间（对应源端 SCAN_CONSTANTS.COOLDOWN_MS）
    static let cooldownInterval: Duration = .milliseconds(50)
    /// 单次导入上限（对应源端 picker maxSelectNumber）
    static let maxImportBatch = 50
}

/// 将字符串哈希为短文件名（对应源端 PhotoImportFileUtils.hashString）
func hashToFilename(_ value: String) -> String {
    var hash = 0
    for char in value.unicodeScalars {
        hash = ((hash << 5) &- hash &+ Int(char.value)) & 0xFFFFFFFF
    }
    let absHash = abs(hash)
    return String(absHash, radix: 36)
}
