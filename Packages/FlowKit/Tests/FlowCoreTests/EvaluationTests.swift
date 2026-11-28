import XCTest
@testable import FlowCore

final class GroupingEvaluationTests: XCTestCase {
    /// a, b は似ている / c は別の構図。2 秒間隔なので連写には当たらない。
    private func makeCatalog() -> (Catalog, [PhotoAsset]) {
        let assets = [makeAsset("a", at: 0), makeAsset("b", at: 2), makeAsset("c", at: 4)]
        let analyses: [PhotoAsset.ID: ImageAnalysis] = [
            assets[0].id: ImageAnalysis(featureVector: vector(angle: 0)),
            assets[1].id: ImageAnalysis(featureVector: vector(angle: 0.3)),  // 距離 ≈ 0.30
            assets[2].id: ImageAnalysis(featureVector: vector(angle: 0.8)),  // b との距離 ≈ 0.49
        ]
        let catalog = Catalog(assets: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }), analyses: analyses)
            .regrouped(with: .default)
        return (catalog, assets)
    }

    func testEvaluationCountsEachKindOfResult() {
        let (catalog, assets) = makeCatalog()
        let ab = PhotoPair(previous: assets[0], next: assets[1])
        let bc = PhotoPair(previous: assets[1], next: assets[2])

        // 正解: a と b は別人なので別、b と c は同じ人なので同じ → 今の判定は両方とも誤り
        let labeled = catalog.with(label: false, for: ab).with(label: true, for: bc)
        XCTAssertEqual(labeled.evaluation, GroupingEvaluation(falseMerges: 1, falseSplits: 1))
        XCTAssertEqual(labeled.evaluation.accuracy, 0)
        XCTAssertEqual(labeled.isPredictedSame(ab), true)
        XCTAssertEqual(labeled.isPredictedSame(bc), false)

        // 正解を直すと両方正しくなる
        let fixed = labeled.with(label: true, for: ab).with(label: false, for: bc)
        XCTAssertEqual(fixed.evaluation, GroupingEvaluation(correctMerges: 1, correctSplits: 1))
        XCTAssertEqual(fixed.evaluation.accuracy, 1)

        // 取り消し
        XCTAssertTrue(fixed.with(label: nil, for: ab).with(label: nil, for: bc).labels.isEmpty)
        XCTAssertNil(catalog.evaluation.accuracy)
    }

    func testLabelsSurviveRegroupingAndUnknownPhotosAreIgnored() {
        let (catalog, assets) = makeCatalog()
        let labeled = catalog
            .with(label: true, for: PhotoPair(previous: assets[0], next: assets[1]))
            .with(label: true, for: PhotoPair(previousPath: "/elsewhere/x.raw", nextPath: "/elsewhere/y.raw"))
        let strict = labeled.regrouped(with: labeled.grouping.with(similarityThreshold: 0.2))
        XCTAssertEqual(strict.labels.count, 2)
        XCTAssertEqual(strict.evaluation, GroupingEvaluation(falseSplits: 1)) // 厳しくしすぎて a と b が分かれた
    }

    func testThresholdSweep() {
        let (catalog, assets) = makeCatalog()
        let labeled = catalog
            .with(label: true, for: PhotoPair(previous: assets[0], next: assets[1]))
            .with(label: false, for: PhotoPair(previous: assets[1], next: assets[2]))
        let sweep = labeled.thresholdSweep([0.2, 0.4, 0.6])
        XCTAssertEqual(sweep.map(\.evaluation.errorCount), [1, 0, 1])
        // 閾値を試しても元のカタログの設定は変わらない
        XCTAssertEqual(labeled.grouping, .default)
    }

    func testLinksByScene() {
        let (catalog, _) = makeCatalog()
        let links = catalog.linksByScene
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[catalog.scenes[0].id]?.map(\.next.fileName), ["b", "c"])
    }

    func testLabelsPersist() throws {
        let (catalog, assets) = makeCatalog()
        let labeled = catalog.with(label: false, for: PhotoPair(previous: assets[0], next: assets[1]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("catalog.json")
        try CatalogStore(fileURL: url).save(labeled)
        let loaded = try XCTUnwrap(try CatalogStore(fileURL: url).load())
        XCTAssertEqual(loaded.labels, labeled.labels)
        XCTAssertEqual(loaded.with(groupingLabels: nil).labels, [:])
    }
}
