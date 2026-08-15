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
        XCTAssertFalse(Route.redPacketUploadGuide(photoID: UUID(), petID: nil).requiresPro)
    }

    func testProFeatureCatalogContainsOnlyImplementedV1Features() {
        XCTAssertEqual(ProFeature.allCases, [
            .petProfiles, .photoStorage, .beadGeneration, .timeline,
            .watermarkFreeExport, .cardTemplates, .timelineExport, .offlineBackup, .albumModes
        ])
        XCTAssertEqual(
            ProFeature.allCases.map(\.localizationKey),
            [
                "paywall.benefit.profiles", "paywall.benefit.photoStorage",
                "paywall.benefit.beadQuota", "paywall.benefit.timeline",
                "paywall.benefit.watermarkFree", "paywall.benefit.cardTemplates",
                "paywall.benefit.timelineExport", "paywall.benefit.offlineBackup",
                "paywall.benefit.albumModes"
            ]
        )
    }
}
