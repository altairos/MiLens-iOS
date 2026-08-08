//  ScanCursorStore —— 上次成功扫描游标的持久化存储。
//
//  iOS 无公开「照片加入相册时间」API（PHAsset 只有 creationDate），
//  「仅扫描新增」的增量策略定义为：
//    以「上次成功扫描开始时刻」为游标，过滤 dateAdded（iOS 上以 creationDate 近似）>= 游标的照片。
//  游标只在扫描成功完成（未取消）时更新；首次无游标 = 全量扫描。
//  局限（诚实标注）：把老照片导入系统相册后，其 creationDate 早于游标，
//  增量扫描不会发现；用户可执行全量扫描兜底。

import Foundation

/// 扫描游标存储协议（测试可注入内存实现）。
protocol ScanCursorStore {
    /// 上次成功扫描的开始时刻（nil = 从未成功扫描，应全量扫描）。
    var lastSuccessfulScan: Date? { get }
    /// 记录一次成功扫描（保存扫描开始时刻）。
    func saveLastSuccessfulScan(_ timestamp: Date)
}

/// UserDefaults 持久化实现（生产环境注入）。
final class UserDefaultsScanCursorStore: ScanCursorStore {
    private let defaults: UserDefaults
    private let key = "lastSuccessfulScanCursor"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastSuccessfulScan: Date? {
        defaults.object(forKey: key) as? Date
    }

    func saveLastSuccessfulScan(_ timestamp: Date) {
        defaults.set(timestamp, forKey: key)
    }
}

/// 内存实现（单元测试注入）。
final class MockScanCursorStore: ScanCursorStore {
    private(set) var lastSuccessfulScan: Date?
    private(set) var savedTimestamps: [Date] = []

    init(lastSuccessfulScan: Date? = nil) {
        self.lastSuccessfulScan = lastSuccessfulScan
    }

    func saveLastSuccessfulScan(_ timestamp: Date) {
        lastSuccessfulScan = timestamp
        savedTimestamps.append(timestamp)
    }
}
