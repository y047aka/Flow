import XCTest
@testable import FlowCore

/// ファイル名から撮影時刻を決めるダミー実装（"<秒>_<角度>.raw"）。
private struct FakeMetadataReader: MetadataReading {
    func readMetadata(at url: URL) throws -> CaptureMetadata {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
        guard let seconds = Double(parts[0]) else { throw URLError(.cannotDecodeContentData) }
        return CaptureMetadata(captureDate: baseDate.addingTimeInterval(seconds))
    }
}

private struct FakeAnalyzer: ImageAnalyzing {
    func analyze(_ asset: PhotoAsset) async throws -> ImageAnalysis {
        let parts = asset.fileURL.deletingPathExtension().lastPathComponent.split(separator: "_")
        return ImageAnalysis(featureVector: vector(angle: Float(parts[1])!), sharpness: Float(parts[1])!)
    }
}

private struct FakeToneMeasurer: ToneMeasuring {
    func luminanceHistogram(for asset: PhotoAsset) async throws -> LuminanceHistogram {
        LuminanceHistogram(samples: [Float](repeating: 0.2, count: 100))
    }
}

final class LibraryPipelineTests: XCTestCase {
    func testEndToEnd() async throws {
        let files = ["0_0.0", "1_0.1", "2_2.0", "172800_2.0", "broken_0"].map { URL(fileURLWithPath: "/card/\($0).raw") }
        let pipeline = LibraryPipeline(
            metadataReader: FakeMetadataReader(),
            analyzer: FakeAnalyzer(),
            maximumConcurrency: 2
        )
        let stages = LockedArray<LibraryPipeline.Stage>()
        let result = try await pipeline.run(files: files, progress: { stages.append($0.stage) })

        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.catalog.assets.count, 4)
        XCTAssertEqual(result.catalog.scenes.count, 2)
        XCTAssertEqual(result.catalog.scenes[0].groups.count, 2)
        // シャープネスが高い 2 枚目がベスト
        let firstGroup = result.catalog.scenes[0].groups[0]
        XCTAssertEqual(result.catalog.assets[firstGroup.bestAssetID!]?.fileName, "1_0.1.raw")
        XCTAssertEqual(Set(stages.values), [.readingMetadata, .analyzing, .grouping])
        // 自動補正は取り込みでは計算しない（撮って出しのまま）
        XCTAssertTrue(result.catalog.autoRecipes.isEmpty)
        XCTAssertEqual(result.catalog.recipe(for: firstGroup.bestAssetID!), DevelopRecipe())
    }
}

final class AutoToneTests: XCTestCase {
    /// シーン 1: [a, b]（ベスト b）、[c]（ベスト c） / シーン 2: [d, e]（ベスト e）
    private func makeCatalog() -> (Catalog, [PhotoAsset]) {
        let assets = ["a", "b", "c", "d", "e"].map { makeAsset($0, at: 0) }
        let ids = assets.map(\.id)
        let catalog = Catalog(
            assets: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }),
            scenes: [
                PhotoScene(startDate: nil, endDate: nil, groups: [
                    SimilarGroup(assetIDs: [ids[0], ids[1]], bestAssetID: ids[1]),
                    SimilarGroup(assetIDs: [ids[2]], bestAssetID: ids[2]),
                ]),
                PhotoScene(startDate: nil, endDate: nil, groups: [
                    SimilarGroup(assetIDs: [ids[3], ids[4]], bestAssetID: ids[4]),
                ]),
            ]
        )
        return (catalog, assets)
    }

    func testPriorityIsFocusedThenBestShotsThenRest() {
        let (catalog, assets) = makeCatalog()
        let names = { (ids: [PhotoAsset.ID]) in ids.compactMap { catalog.assets[$0]?.fileName } }
        XCTAssertEqual(names(catalog.autoTonePriority()), ["b", "c", "e", "a", "d"])
        XCTAssertEqual(names(catalog.autoTonePriority(focusedOn: assets[3].id)), ["d", "b", "c", "e", "a"])
    }

    func testCompletedPhotosAreSkipped() {
        let (catalog, assets) = makeCatalog()
        let updated = catalog
            .with(autoRecipe: DevelopRecipe(exposure: 0.5), for: assets[1].id)
            .with(autoRecipe: DevelopRecipe(), for: assets[3].id)
        XCTAssertEqual(updated.autoTonePriority(focusedOn: assets[3].id).compactMap { updated.assets[$0]?.fileName }, ["c", "e", "a"])
        XCTAssertEqual(updated.autoToneProgress.completed, 2)
        XCTAssertEqual(updated.autoToneProgress.total, 5)
        XCTAssertEqual(updated.recipe(for: assets[1].id).exposure, 0.5)
        // 元のカタログは変わらない
        XCTAssertTrue(catalog.autoRecipes.isEmpty)
    }

    func testRecipeForUnknownAssetIsIgnored() {
        let (catalog, _) = makeCatalog()
        XCTAssertTrue(catalog.with(autoRecipe: DevelopRecipe(exposure: 1), for: UUID()).autoRecipes.isEmpty)
    }

    func testServiceEstimatesFromMeasuredHistogram() async throws {
        let recipe = try await AutoToneService(measurer: FakeToneMeasurer()).recipe(for: makeAsset("a", at: 0))
        XCTAssertGreaterThan(recipe.exposure, 0) // 暗いヒストグラム → 明るくする
    }
}

final class RawFileScannerTests: XCTestCase {
    func testFindsRawFilesRecursively() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub = root.appendingPathComponent("DCIM/100CANON")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for name in ["IMG_0001.CR3", "IMG_0001.JPG", "IMG_0002.cr3"] {
            try Data().write(to: sub.appendingPathComponent(name))
        }
        try Data().write(to: root.appendingPathComponent("DSC0001.ARW"))
        let found = try RawFileScanner().scan(root).map(\.lastPathComponent)
        XCTAssertEqual(Set(found), ["IMG_0001.CR3", "IMG_0002.cr3", "DSC0001.ARW"])
    }
}

final class LockedArray<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [T] = []
    func append(_ value: T) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [T] { lock.lock(); defer { lock.unlock() }; return storage }
}
