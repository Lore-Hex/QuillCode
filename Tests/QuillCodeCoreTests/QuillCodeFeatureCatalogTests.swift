@testable import QuillCodeCore
import XCTest

final class QuillCodeFeatureCatalogTests: XCTestCase {
    func testCatalogHasOneDefinitionForEveryFeatureInStableOrder() {
        XCTAssertEqual(QuillCodeFeatureCatalog.all.map(\.feature), QuillCodeFeature.allCases)
        XCTAssertEqual(Set(QuillCodeFeatureCatalog.all.map(\.feature)).count, QuillCodeFeature.allCases.count)
    }

    func testOnlyBetaFeaturesExposePresentationCopy() {
        for definition in QuillCodeFeatureCatalog.all {
            if definition.stage == .beta {
                XCTAssertNotNil(definition.displayName)
                XCTAssertNotNil(definition.description)
                XCTAssertNotNil(definition.announcement)
            } else {
                XCTAssertNil(definition.displayName)
                XCTAssertNil(definition.description)
                XCTAssertNil(definition.announcement)
            }
        }
    }

    func testRuntimeEnablementIsLimitedToImplementedBehavior() {
        XCTAssertEqual(
            QuillCodeFeatureCatalog.all.filter(\.supportsRuntimeEnablement).map(\.feature),
            [.memories]
        )
    }
}
