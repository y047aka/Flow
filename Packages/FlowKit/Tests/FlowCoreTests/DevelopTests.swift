import XCTest
@testable import FlowCore

final class AutoToneEstimatorTests: XCTestCase {
    func testWellExposedImageIsLeftAlone() {
        let samples = (0..<1000).map { Float($0 % 100) / 100 * 0.84 }  // 中央値 ≈ 0.42
        let recipe = AutoToneEstimator().estimate(from: LuminanceHistogram(samples: samples))
        XCTAssertEqual(recipe.exposure, 0)
        XCTAssertEqual(recipe.highlights, 0)
        XCTAssertEqual(recipe, DevelopRecipe())
    }

    func testUnderexposedImageIsBrightenedConservatively() {
        let samples = (0..<1000).map { Float($0 % 100) / 100 * 0.3 + 0.05 }  // 中央値 ≈ 0.2
        let recipe = AutoToneEstimator().estimate(from: LuminanceHistogram(samples: samples))
        XCTAssertGreaterThan(recipe.exposure, 0.5)
        XCTAssertLessThanOrEqual(recipe.exposure, 1.0)
    }

    func testClippedHighlightsAreRecovered() {
        var samples = [Float](repeating: 0.45, count: 900)
        samples += [Float](repeating: 1.0, count: 100)  // 10% 白飛び
        let recipe = AutoToneEstimator().estimate(from: LuminanceHistogram(samples: samples))
        XCTAssertGreaterThan(recipe.highlights, 0.5)
    }

    func testEmptyHistogramGivesNeutralRecipe() {
        XCTAssertEqual(AutoToneEstimator().estimate(from: LuminanceHistogram(bins: [])), DevelopRecipe())
    }
}

final class DevelopPresetTests: XCTestCase {
    func testAsShotIgnoresAutoTone() {
        let result = DevelopPreset.asShot.apply(to: DevelopRecipe(exposure: 0.8, highlights: 0.4))
        XCTAssertEqual(result.exposure, 0)
        XCTAssertEqual(result.highlights, 0)
    }

    func testPresetAddsAndClamps() {
        let result = DevelopPreset.crisp.apply(to: DevelopRecipe(vibrance: 0.95))
        XCTAssertEqual(result.vibrance, 1)
        XCTAssertEqual(result.contrast, 0.15, accuracy: 1e-9)
    }

    func testMonochrome() {
        XCTAssertTrue(DevelopPreset.monochrome.apply(to: DevelopRecipe()).monochrome)
    }
}

final class CatalogDerivationTests: XCTestCase {
    func testWithReturnsNewCatalogAndKeepsOriginal() {
        let original = Catalog(presetID: DevelopPreset.neutral.id)
        let changed = original.with(presetID: DevelopPreset.crisp.id).with(sourceFolderBookmark: Data([1]))
        XCTAssertEqual(original.preset, .neutral)
        XCTAssertNil(original.sourceFolderBookmark)
        XCTAssertEqual(changed.preset, .crisp)
        XCTAssertEqual(changed.sourceFolderBookmark, Data([1]))
        XCTAssertNil(changed.with(sourceFolderBookmark: nil).sourceFolderBookmark)
    }
}

final class FunctionalHelperTests: XCTestCase {
    func testChunked() {
        XCTAssertEqual([1, 2, 4, 5, 7].chunked { $1 - $0 == 1 }, [[1, 2], [4, 5], [7]])
        XCTAssertEqual([Int]().chunked { _, _ in true }, [])
    }

    func testCumulativeSums() {
        XCTAssertEqual([1, 2, 3].cumulativeSums(), [1, 3, 6])
    }
}

final class CatalogTests: XCTestCase {
    func testRoundTripThroughStore() throws {
        let asset = makeAsset("a.cr3", at: 0)
        let recipe = DevelopRecipe(whiteBalance: .custom(temperature: 5200, tint: 4))
        let catalog = Catalog(
            assets: [asset.id: asset],
            analyses: [asset.id: ImageAnalysis(featureVector: vector(angle: 0), aestheticsScore: 0.3)],
            autoRecipes: [asset.id: recipe],
            presetID: DevelopPreset.soft.id
        ).regrouped(by: CatalogGrouper())

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("catalog.json")
        let store = CatalogStore(fileURL: url)
        try store.save(catalog)
        let loaded = try XCTUnwrap(try store.load())

        XCTAssertEqual(loaded.assets, catalog.assets)
        XCTAssertEqual(loaded.analyses, catalog.analyses)
        XCTAssertEqual(loaded.autoRecipes, catalog.autoRecipes)
        XCTAssertEqual(loaded.scenes, catalog.scenes)
        XCTAssertEqual(loaded.preset, .soft)
        XCTAssertEqual(loaded.bestAssets.map(\.id), [asset.id])
    }
}
