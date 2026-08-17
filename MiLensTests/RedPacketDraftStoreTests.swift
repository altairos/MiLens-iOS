//  RedPacketDraftStoreTests —— 红包封面草稿本地持久化测试（对应红包封面开发计划 §5）。
//  覆盖：save/load 往返 / 覆盖式保存 / listAll 排序与过滤 / 抠图 PNG 往返 /
//  delete 联动删除 / 损坏 JSON 跳过。全部使用隔离临时目录，tearDown 清理。

import XCTest
import MiLensKit
@testable import MiLens

@MainActor
final class RedPacketDraftStoreTests: XCTestCase {

    private var dir: URL!
    private var store: RedPacketDraftStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RedPacketDraftStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = RedPacketDraftStore(draftsDir: dir)
    }

    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        dir = nil
        store = nil
    }

    private func makeDraft(petName: String = "咪咪",
                           updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
                           layers: [RedPacketLayer] = []) -> RedPacketCoverDraft {
        RedPacketCoverDraft(templateID: "newYearRed", templateRevision: 1,
                            layers: layers, petName: petName,
                            coverTitle: "新年快乐", updatedAt: updatedAt)
    }

    // MARK: - save / load

    /// 保存后加载往返一致（含图层与字段）。
    func testSaveLoadRoundTrip() throws {
        let layer = RedPacketLayer(id: "pet", kind: .pet, x: 100, y: 200,
                                   width: 300, height: 400, resourceRef: "pet.png")
        let draft = makeDraft(layers: [layer])

        try store.save(draft)

        let loaded = try store.load(id: draft.id)
        XCTAssertEqual(loaded, draft, "JSON 往返后草稿一致（含图层）")
    }

    /// 加载不存在的草稿返回 nil（非抛错）。
    func testLoadMissingReturnsNil() throws {
        XCTAssertNil(try store.load(id: UUID()))
    }

    /// 同 ID 二次保存为覆盖式。
    func testSaveOverwritesSameID() throws {
        let draft = makeDraft(petName: "第一版")
        try store.save(draft)

        let updated = RedPacketCoverDraft(
            id: draft.id, templateID: "newYearRed", templateRevision: 2,
            petName: "第二版", coverTitle: "改标题")
        try store.save(updated)

        let loaded = try store.load(id: draft.id)
        XCTAssertEqual(loaded?.petName, "第二版", "同 ID 覆盖保存")
        XCTAssertEqual(loaded?.templateRevision, 2)
    }

    // MARK: - listAll

    /// listAll 按更新时间降序，且只列 json（抠图 PNG 不进列表）。
    func testListAllSortedByUpdatedAtDescendingAndJSONOnly() throws {
        let older = makeDraft(petName: "旧", updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeDraft(petName: "新", updatedAt: Date(timeIntervalSince1970: 2_000))
        try store.save(older)
        try store.save(newer)
        try store.saveCutoutPNG(Data([0x89, 0x50, 0x4E, 0x47]), for: older.id)

        let all = try store.listAll()
        XCTAssertEqual(all.map(\.petName), ["新", "旧"], "按 updatedAt 降序")
        XCTAssertEqual(all.count, 2, "PNG 文件不计入草稿列表")
    }

    /// 损坏的 JSON 文件被 listAll 跳过，不影响其余草稿。
    func testListAllSkipsCorruptJSON() throws {
        let good = makeDraft(petName: "完好")
        try store.save(good)

        let corruptID = UUID()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let corruptURL = dir.appendingPathComponent(String(corruptID.uuidString + ".json"))
        try Data("{ not valid json !!".utf8).write(to: corruptURL)

        let all = try store.listAll()
        XCTAssertEqual(all.map(\.petName), ["完好"], "损坏文件被静默跳过")
    }

    // MARK: - 抠图 PNG

    /// 抠图 PNG 保存与读取往返。
    func testCutoutPNGRoundTrip() throws {
        let id = UUID()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try store.saveCutoutPNG(png, for: id)

        XCTAssertEqual(store.loadCutoutPNG(id: id), png)
    }

    /// 读取不存在的抠图 PNG 返回 nil。
    func testLoadMissingCutoutPNGReturnsNil() {
        XCTAssertNil(store.loadCutoutPNG(id: UUID()))
    }

    // MARK: - delete

    /// delete 联动删除草稿 JSON 与同 ID 抠图 PNG；重复 delete 幂等不抛。
    func testDeleteRemovesDraftAndCutoutAndIsIdempotent() throws {
        let id = UUID()
        try store.save(makeDraft())
        try store.saveCutoutPNG(Data([0xFF]), for: id)

        try store.delete(id: id)
        XCTAssertNil(try store.load(id: id))
        XCTAssertNil(store.loadCutoutPNG(id: id))

        try store.delete(id: id)
        XCTAssertNoThrow(try store.delete(id: UUID()), "删除不存在的 ID 不抛")
    }
}