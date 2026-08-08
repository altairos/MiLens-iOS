//  GalleryFilterLogicTests —— 相册宠物筛选 chip 与照片过滤纯逻辑测试。
//
//  行为规格（UI-DESIGN.md §5.2 + 源端 GalleryFilterPanel）：
//  - chip 列表 = 「全部」置顶 + 各宠物按输入顺序（设计稿无「无归属」chip）；
//  - 选中态互斥：selectedPetID nil → 「全部」选中，具体 ID → 对应宠物选中，
//    未知 ID → 无任何 chip 选中；
//  - filterPhotos：nil = 全部（保持顺序），具体 ID = 仅匹配宠物，未关联照片被排除。

import XCTest
@testable import MiLensKit

final class GalleryFilterLogicTests: XCTestCase {

    private var petA: GalleryFilterPet!
    private var petB: GalleryFilterPet!

    override func setUp() {
        super.setUp()
        petA = GalleryFilterPet(name: "小橘")
        petB = GalleryFilterPet(name: "旺财")
    }

    // MARK: - buildChips

    func testBuildChipsWithNoPetsYieldsOnlyAllChip() {
        let chips = GalleryFilterLogic.buildChips(pets: [], selectedPetID: nil)
        XCTAssertEqual(chips.count, 1)
        XCTAssertEqual(chips[0].id, GalleryFilterLogic.allChipID)
        XCTAssertNil(chips[0].petID)
        XCTAssertEqual(chips[0].title, "全部")
        XCTAssertTrue(chips[0].isSelected)
    }

    func testBuildChipsOrderAllFirstThenPets() {
        let chips = GalleryFilterLogic.buildChips(pets: [petA, petB], selectedPetID: nil)
        XCTAssertEqual(chips.count, 3)
        XCTAssertEqual(chips.map(\.title), ["全部", "小橘", "旺财"])
        // chip id 稳定：all + 宠物 UUID 字符串
        XCTAssertEqual(chips[1].id, petA.id.uuidString)
        XCTAssertEqual(chips[2].id, petB.id.uuidString)
        XCTAssertEqual(chips.map(\.petID), [nil, petA.id, petB.id])
    }

    func testBuildChipsMarksSelectedPet() {
        let chips = GalleryFilterLogic.buildChips(pets: [petA, petB], selectedPetID: petB.id)
        XCTAssertEqual(chips.map(\.isSelected), [false, false, true])
    }

    func testBuildChipsMarksAllWhenNoSelection() {
        let chips = GalleryFilterLogic.buildChips(pets: [petA, petB], selectedPetID: nil)
        XCTAssertEqual(chips.map(\.isSelected), [true, false, false])
    }

    func testBuildChipsUnknownSelectedPetIDSelectsNothing() {
        let chips = GalleryFilterLogic.buildChips(pets: [petA, petB], selectedPetID: UUID())
        // 未知 ID：全部与宠物 chip 均不选中（选中态互斥且无泄漏）
        XCTAssertTrue(chips.map(\.isSelected).allSatisfy { !$0 })
    }

    func testBuildChipsTitlesUsePetNamesAsIs() {
        let chips = GalleryFilterLogic.buildChips(pets: [petA], selectedPetID: petA.id)
        XCTAssertEqual(chips[1].title, "小橘")
    }

    func testBuildChipsIDsAreUnique() {
        let chips = GalleryFilterLogic.buildChips(pets: [petA, petB], selectedPetID: nil)
        let ids = chips.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - filterPhotos

    func testFilterPhotosNilPetIDReturnsAllInOrder() {
        let photos = [
            GalleryPhoto(id: UUID(), takenAt: nil, petID: petA.id),
            GalleryPhoto(id: UUID(), takenAt: nil, petID: nil),
            GalleryPhoto(id: UUID(), takenAt: nil, petID: petB.id),
        ]
        XCTAssertEqual(GalleryFilterLogic.filterPhotos(photos, petID: nil), photos)
    }

    func testFilterPhotosSelectsMatchingPetOnly() {
        let a1 = GalleryPhoto(id: UUID(), takenAt: nil, petID: petA.id)
        let b1 = GalleryPhoto(id: UUID(), takenAt: nil, petID: petB.id)
        let a2 = GalleryPhoto(id: UUID(), takenAt: nil, petID: petA.id)
        let result = GalleryFilterLogic.filterPhotos([a1, b1, a2], petID: petA.id)
        XCTAssertEqual(result.map(\.id), [a1.id, a2.id])
    }

    func testFilterPhotosNoMatchReturnsEmpty() {
        let photos = [GalleryPhoto(id: UUID(), takenAt: nil, petID: petA.id)]
        XCTAssertEqual(GalleryFilterLogic.filterPhotos(photos, petID: petB.id), [])
    }

    func testFilterPhotosExcludesUnassignedWhenPetSelected() {
        let assigned = GalleryPhoto(id: UUID(), takenAt: nil, petID: petA.id)
        let unassigned = GalleryPhoto(id: UUID(), takenAt: nil, petID: nil)
        let result = GalleryFilterLogic.filterPhotos([unassigned, assigned], petID: petA.id)
        XCTAssertEqual(result.map(\.id), [assigned.id])
    }

    func testFilterPhotosPreservesInputOrder() {
        let a1 = GalleryPhoto(id: UUID(), takenAt: nil, petID: petA.id)
        let a2 = GalleryPhoto(id: UUID(), takenAt: nil, petID: petA.id)
        let a3 = GalleryPhoto(id: UUID(), takenAt: nil, petID: petA.id)
        let result = GalleryFilterLogic.filterPhotos([a3, a1, a2], petID: petA.id)
        XCTAssertEqual(result.map(\.id), [a3.id, a1.id, a2.id])
    }
}
