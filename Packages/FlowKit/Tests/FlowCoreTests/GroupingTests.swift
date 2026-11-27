import XCTest
@testable import FlowCore

final class SceneSegmenterTests: XCTestCase {
    func testSplitsOnTimeGap() {
        let assets = [
            makeAsset("c.raw", at: 2000),
            makeAsset("a.raw", at: 0),
            makeAsset("b.raw", at: 30),
            makeAsset("d.raw", at: 2010),
        ]
        let scenes = SceneSegmenter().segment(assets)
        XCTAssertEqual(scenes.map { $0.map(\.fileName) }, [["a.raw", "b.raw"], ["c.raw", "d.raw"]])
    }

    func testSplitsOnDistance() {
        let tokyo = GeoCoordinate(latitude: 35.681, longitude: 139.767)
        let yokohama = GeoCoordinate(latitude: 35.466, longitude: 139.622)
        let assets = [makeAsset("a.raw", at: 0, location: tokyo), makeAsset("b.raw", at: 60, location: yokohama)]
        XCTAssertEqual(SceneSegmenter().segment(assets).count, 2)
    }

    func testUndatedAssetsGoLast() {
        let assets = [makeAsset("x.raw", at: nil), makeAsset("a.raw", at: 0)]
        let scenes = SceneSegmenter().segment(assets)
        XCTAssertEqual(scenes.map { $0.map(\.fileName) }, [["a.raw"], ["x.raw"]])
    }

    func testSameSecondIsOrderedByFileName() {
        let assets = [makeAsset("b.raw", at: 0), makeAsset("a.raw", at: 0)]
        XCTAssertEqual(SceneSegmenter().segment(assets).first?.map(\.fileName), ["a.raw", "b.raw"])
    }
}

final class SimilarityClustererTests: XCTestCase {
    func testGroupsSimilarConsecutiveShots() {
        let a = makeAsset("a", at: 0), b = makeAsset("b", at: 1), c = makeAsset("c", at: 2), d = makeAsset("d", at: 3)
        let analyses: [PhotoAsset.ID: ImageAnalysis] = [
            a.id: ImageAnalysis(featureVector: vector(angle: 0)),
            b.id: ImageAnalysis(featureVector: vector(angle: 0.1)),
            c.id: ImageAnalysis(featureVector: vector(angle: 2.0)),  // 全く違う構図
            d.id: ImageAnalysis(featureVector: vector(angle: 2.05)),
        ]
        let groups = SimilarityClusterer().cluster([a, b, c, d], analyses: analyses)
        XCTAssertEqual(groups.map { $0.map(\.fileName) }, [["a", "b"], ["c", "d"]])
    }

    func testTimeGapBreaksGroupEvenIfSimilar() {
        let a = makeAsset("a", at: 0), b = makeAsset("b", at: 600)
        let analyses = [a.id: ImageAnalysis(featureVector: vector(angle: 0)), b.id: ImageAnalysis(featureVector: vector(angle: 0))]
        XCTAssertEqual(SimilarityClusterer().cluster([a, b], analyses: analyses).count, 2)
    }

    func testMissingAnalysisMakesSingleton() {
        let a = makeAsset("a", at: 0), b = makeAsset("b", at: 1)
        let analyses = [a.id: ImageAnalysis(featureVector: vector(angle: 0))]
        XCTAssertEqual(SimilarityClusterer().cluster([a, b], analyses: analyses).count, 2)
    }

    func testComparisonWindowToleratesDrift() {
        // a→b→c と少しずつ構図が変わる（パン撮影など）。隣同士が近ければ同じグループ。
        let assets = (0..<4).map { makeAsset("p\($0)", at: TimeInterval($0)) }
        var analyses: [PhotoAsset.ID: ImageAnalysis] = [:]
        for (i, asset) in assets.enumerated() { analyses[asset.id] = ImageAnalysis(featureVector: vector(angle: Float(i) * 0.4)) }
        XCTAssertEqual(SimilarityClusterer().cluster(assets, analyses: analyses).count, 1)
    }
}

final class BestShotSelectorTests: XCTestCase {
    func testPrefersSharpAndGoodFaces() {
        let ids = (0..<3).map { _ in UUID() }
        let analyses: [UUID: ImageAnalysis] = [
            ids[0]: ImageAnalysis(aestheticsScore: 0.5, sharpness: 0.2, faceCount: 1, minimumFaceQuality: 0.3),  // ブレ・目つむり
            ids[1]: ImageAnalysis(aestheticsScore: 0.4, sharpness: 0.9, faceCount: 1, minimumFaceQuality: 0.8),
            ids[2]: ImageAnalysis(aestheticsScore: 0.6, isUtility: true, sharpness: 0.8),
        ]
        XCTAssertEqual(BestShotSelector().selectBest(from: ids, analyses: analyses), ids[1])
    }

    func testTieKeepsFirst() {
        let ids = [UUID(), UUID()]
        XCTAssertEqual(BestShotSelector().selectBest(from: ids, analyses: [:]), ids[0])
    }
}
