import XCTest
@testable import MiLens

final class RouteTests: XCTestCase {
    func testProRoutesAreGated() {
        XCTAssertTrue(Route.editor(photoID: UUID()).requiresPro)
        XCTAssertTrue(Route.beadPhotoPicker.requiresPro)
        XCTAssertTrue(Route.beadPattern(photoID: UUID()).requiresPro)
    }

    func testFreeRoutesAreNotGated() {
        XCTAssertFalse(Route.gallery.requiresPro)
        XCTAssertFalse(Route.photoView(photoID: UUID()).requiresPro)
        XCTAssertFalse(Route.petCardPhotoPicker.requiresPro)
        XCTAssertFalse(Route.petCard(photoID: UUID()).requiresPro)
        XCTAssertFalse(Route.petProfile(petID: UUID()).requiresPro)
        XCTAssertFalse(Route.timeline.requiresPro)
    }

    func testProFeatureCatalogContainsOnlyImplementedV1Features() {
        XCTAssertEqual(ProFeature.allCases, [.beadStudio, .photoEditor])
        XCTAssertEqual(
            ProFeature.allCases.map(\.localizationKey),
            ["paywall.benefit.export", "paywall.benefit.create"]
        )
    }
}
