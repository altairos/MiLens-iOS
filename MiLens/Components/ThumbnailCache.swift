//  ThumbnailCache —— UIImage 内存 LRU 缓存（对应源端 utils/ThumbnailCache.ets）。
//
//  源端用 Map 维护插入顺序实现 LRU；iOS 用 NSMutableDictionary + 访问时间戳实现等价语义。
//  超过 maxSize 时淘汰最久未访问的条目；淘汰计数达阈值时异步清理磁盘缩略图目录。
//
//  线程安全：内部用 NSLock 保护（读/写/淘汰原子化），可跨 actor 安全调用。
//  不持有 CGImageSource / 文件句柄——只缓存已解码的 UIImage（解码本身在 ThumbnailImage 后台 task 完成）。
//
//  内存压力响应：监听 UIApplication.didReceiveMemoryWarningNotification，
//  收到通知时清空全部缓存（源端在 EntryAbility shutdownListener 同步调用 ThumbnailCache.clear）。
//
//  DESIGN.md §3：资源生命周期——图像解码缓冲有上限。

import UIKit
import Foundation
import os

/// 缩略图内存 LRU 缓存（线程安全）。
final class ThumbnailCache {

    private let logger = Logger(subsystem: "com.milens.app", category: "ThumbnailCache")

    /// 缓存条目（UIImage + 最后访问时间）。
    private struct Entry {
        let image: UIImage
        var lastAccess: TimeInterval
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    /// 按访问时间排序的 key 数组（最旧在前），避免每次淘汰全表扫描。
    private var accessOrder: [String] = []

    /// 最大条目数（源端默认 100）。
    private let maxSize: Int
    /// 每淘汰多少条目触发一次磁盘清理（源端 DISK_CLEANUP_INTERVAL = 20）。
    private let diskCleanupInterval: Int
    /// 累计淘汰计数。
    private var evictCount = 0

    /// 磁盘缩略图目录（nil = 不做磁盘清理）。
    private let diskDir: String?
    /// 磁盘缓存上限（字节，源端默认 100MB）。
    private let maxDiskBytes: Int64

    init(maxSize: Int = 100,
         diskCleanupInterval: Int = 20,
         diskDir: String? = nil,
         maxDiskBytes: Int64 = 100 * 1024 * 1024) {
        self.maxSize = maxSize
        self.diskCleanupInterval = diskCleanupInterval
        self.diskDir = diskDir
        self.maxDiskBytes = maxDiskBytes
        // 监听内存警告——收到即清空（源端 shutdownListener 语义）。
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 读写

    /// 获取缓存的 UIImage（命中时更新访问时间，移到队尾）。
    func get(_ key: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[key] else { return nil }
        entry.lastAccess = Date().timeIntervalSince1970
        entries[key] = entry
        // 维护访问顺序：移到末尾
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(key)
        return entry.image
    }

    /// 存入缓存；超限时淘汰最久未访问的条目。
    func put(_ key: String, image: UIImage) {
        lock.lock()
        defer { lock.unlock() }
        if entries[key] != nil {
            // 已存在：更新访问时间即可
            entries[key] = Entry(image: image, lastAccess: Date().timeIntervalSince1970)
            if let idx = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: idx)
            }
            accessOrder.append(key)
            return
        }
        // 新条目：超限则淘汰
        while entries.count >= maxSize && !accessOrder.isEmpty {
            let oldest = accessOrder.removeFirst()
            entries.removeValue(forKey: oldest)
            evictCount += 1
            if evictCount >= diskCleanupInterval {
                evictCount = 0
                // 磁盘清理在锁外异步执行（避免持锁做 IO）
                let dir = diskDir
                let limit = maxDiskBytes
                Task.detached(priority: .utility) { [weak self] in
                    self?.trimDiskCache(dir: dir, maxBytes: limit)
                }
            }
        }
        entries[key] = Entry(image: image, lastAccess: Date().timeIntervalSince1970)
        accessOrder.append(key)
    }

    /// 是否存在缓存（不更新访问时间）。
    func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[key] != nil
    }

    /// 清空全部缓存（内存警告 / 主动释放）。
    func clear() {
        lock.lock()
        entries.removeAll()
        accessOrder.removeAll()
        evictCount = 0
        lock.unlock()
    }

    /// 当前缓存条目数。
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    // MARK: - 内存警告

    @objc private func handleMemoryWarning() {
        logger.info("内存警告：清空缩略图缓存（\(self.count) 条）")
        clear()
    }

    // MARK: - 磁盘清理

    /// 清理磁盘缩略图目录：按修改时间从旧到新删除，直到总大小 < maxBytes。
    /// 与源端 cleanupDiskCache 语义一致。
    private func trimDiskCache(dir: String?, maxBytes: Int64) {
        guard let dir else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                       includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                       options: [.skipsHiddenFiles]) else { return }
        var sized: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for url in files {
            guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = vals.contentModificationDate,
                  let size = vals.fileSize else { continue }
            sized.append((url: url, size: Int64(size), date: date))
            total += Int64(size)
        }
        guard total > maxBytes else { return }
        // 按修改时间升序（最旧先删）
        sized.sort { $0.date < $1.date }
        var freed: Int64 = 0
        for item in sized {
            if total - freed <= maxBytes { break }
            if (try? fm.removeItem(at: item.url)) != nil {
                freed += item.size
            }
        }
        if freed > 0 {
            logger.info("磁盘缓存清理完成，释放 \(String(format: "%.1f", Double(freed) / 1024.0 / 1024.0))MB")
        }
    }
}
