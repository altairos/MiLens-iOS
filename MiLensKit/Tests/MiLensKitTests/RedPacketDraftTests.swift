import XCTest
@testable import MiLensKit

// RedPacketDraftTests — 草稿 JSON 往返一致性测试（对应红包封面开发计划 §5）。
final class RedPacketDraftTests: XCTestCase {

    private var defaultTemplate: RedPacketTemplate { RedPacketTemplateCatalog.firstFreeTemplate }

    // MARK: - 创建

    func testCreateFromTemplate() {
        let draft = RedPacketCoverDraft.create(from: defaultTemplate, petName: "咪咪")
        XCTAssertEqual(draft.templateID, defaultTemplate.id)
        XCTAssertEqual(draft.templateRevision, defaultTemplate.revision)
        XCTAssertEqual(draft.petName, "咪咪")
        XCTAssertEqual(draft.coverTitle, "咪咪")
        XCTAssertFalse(draft.layers.isEmpty)
    }

    func testCreateFromTemplateFallbackTitle() {
        let draft = RedPacketCoverDraft.create(from: defaultTemplate)
        XCTAssertEqual(draft.coverTitle, "恭喜发财")
    }

    func testCreateFromTemplateHasLayers() {
        let draft = RedPacketCoverDraft.create(from: defaultTemplate)
        XCTAssertNotNil(draft.layers.first { $0.kind == .templateBackground })
        XCTAssertNotNil(draft.layers.first { $0.kind == .pet })
        XCTAssertNotNil(draft.layers.first { $0.kind == .text })
    }

    // MARK: - JSON 往返

    func testJSONRoundTrip() throws {
        let original = RedPacketCoverDraft.create(from: defaultTemplate, petName: "咪咪")
        let data = try original.encodeJSON()
        let decoded = try RedPacketCoverDraft.decodeJSON(data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.templateID, original.templateID)
        XCTAssertEqual(decoded.templateRevision, original.templateRevision)
        XCTAssertEqual(decoded.petName, original.petName)
        XCTAssertEqual(decoded.coverTitle, original.coverTitle)
        XCTAssertEqual(decoded.layers.count, original.layers.count)
    }

    func testJSONRoundTripWithSourcePhotoID() throws {
        let photoID = UUID()
        let original = RedPacketCoverDraft.create(
            from: defaultTemplate, sourcePhotoID: photoID, petName: "咪咪"
        )
        let data = try original.encodeJSON()
        let decoded = try RedPacketCoverDraft.decodeJSON(data)
        XCTAssertEqual(decoded.sourcePhotoID, photoID)
    }

    // MARK: - 版本字段持久化

    func testTemplateRevisionPersisted() throws {
        let gold = RedPacketTemplateCatalog.fortuneGold
        let draft = RedPacketCoverDraft.create(from: gold, petName: "咪咪")
        let data = try draft.encodeJSON()
        let decoded = try RedPacketCoverDraft.decodeJSON(data)
        XCTAssertEqual(decoded.templateRevision, gold.revision)
    }

    func testLayersPersisted() throws {
        var draft = RedPacketCoverDraft.create(from: defaultTemplate, petName: "咪咪")
        // 添加配饰层
        var accessory = makeRedPacketTextLayer(text: "", x: 200, y: 200)
        accessory.kind = .accessory
        accessory.resourceRef = "sticker.png"
        draft.layers.append(accessory)

        let data = try draft.encodeJSON()
        let decoded = try RedPacketCoverDraft.decodeJSON(data)
        XCTAssertEqual(decoded.layers.count, draft.layers.count)
        let decodedAccessory = decoded.layers.first { $0.kind == .accessory }
        XCTAssertEqual(decodedAccessory?.resourceRef, "sticker.png")
    }

    func testTimestampsPersisted() throws {
        let createdAt = Date(timeIntervalSince1970: 1700000000)
        let updatedAt = Date(timeIntervalSince1970: 1700000100)
        let draft = RedPacketCoverDraft(
            templateID: defaultTemplate.id,
            templateRevision: defaultTemplate.revision,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let data = try draft.encodeJSON()
        let decoded = try RedPacketCoverDraft.decodeJSON(data)
        // ISO8601 精度有秒级截断，允许小误差
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, updatedAt.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - 空草稿

    func testEmptyDraftRoundTrip() throws {
        let draft = RedPacketCoverDraft(
            templateID: "test",
            templateRevision: 1
        )
        let data = try draft.encodeJSON()
        let decoded = try RedPacketCoverDraft.decodeJSON(data)
        XCTAssertTrue(decoded.layers.isEmpty)
        XCTAssertNil(decoded.sourcePhotoID)
    }
}
