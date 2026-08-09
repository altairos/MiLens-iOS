import XCTest
@testable import MiLens

final class RouteTests: XCTestCase {
    func testCurrentRoutesRemainFreeToExplore() {
        XCTAssertFalse(Route.editor(photoID: UUID()).requiresPro)
        XCTAssertFalse(Route.beadPhotoPicker.requiresPro)
        XCTAssertFalse(Route.beadPattern(photoID: UUID()).requiresPro)
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
        XCTAssertEqual(ProFeature.allCases, [.petProfiles, .beadGeneration, .timeline])
        XCTAssertEqual(
            ProFeature.allCases.map(\.localizationKey),
            ["paywall.benefit.profiles", "paywall.benefit.beadQuota", "paywall.benefit.timeline"]
        )
    }
}
