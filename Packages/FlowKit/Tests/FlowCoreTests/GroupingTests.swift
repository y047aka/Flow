import XCTest
@testable import FlowCore

final class SceneSegmenterTests: XCTestCase {
    // baseDate は 2023-11-14 22:13:20 UTC。日付判定は UTC・朝 4 時切り替えで行う。
    let segmenter = SceneSegmenter(configuration: .init(timeZone: TimeZone(identifier: "UTC")!))
    let park = GeoCoordinate(latitude: 35.6715, longitude: 139.6950)

    func testWithoutLocationSplitsOnlyByShootingDay() {
        // 位置情報が無ければ、撮影間隔が空いても同じ撮影日なら 1 シーン。朝 4 時を越えたら別シーン。
        let assets = [
            makeAsset("c.raw", at: 2000),
            makeAsset("a.raw", at: 0),
            makeAsset("b.raw", at: 30),
            makeAsset("d.raw", at: 21000),
        ]
        XCTAssertEqual(segmenter.segment(assets).map { $0.map(\.fileName) }, [["a.raw", "b.raw", "c.raw"], ["d.raw"]])
    }

    func testSplitsOnDistance() {
        let tokyo = GeoCoordinate(latitude: 35.681, longitude: 139.767)
        let yokohama = GeoCoordinate(latitude: 35.466, longitude: 139.622)
        let assets = [makeAsset("a.raw", at: 0, location: tokyo), makeAsset("b.raw", at: 60, location: yokohama)]
        XCTAssertEqual(segmenter.segment(assets).count, 2)
    }

    func testSameLocationKeepsSceneDespiteTimeGap() {
        // 同じ公園で 1 時間休憩を挟んでも、位置情報があれば同じシーン
        let assets = [makeAsset("a.raw", at: 0, location: park), makeAsset("b.raw", at: 3600, location: park)]
        XCTAssertEqual(segmenter.segment(assets).count, 1)
    }

    func testVeryLongGapAtSameLocationSplits() {
        let assets = [makeAsset("a.raw", at: -20000, location: park), makeAsset("b.raw", at: -5000, location: park)]
        XCTAssertEqual(segmenter.segment(assets).count, 2)
    }

    func testGradualMovementSplitsAgainstSceneCenter() {
        // 約 200m ずつ北へ移動。隣同士は近いが、シーンの中心からは離れていく。
        let assets = (0..<8).map { i in
            makeAsset("p\(i).raw", at: TimeInterval(i * 60),
                      location: GeoCoordinate(latitude: park.latitude + Double(i) * 0.0018, longitude: park.longitude))
        }
        XCTAssertGreaterThan(segmenter.segment(assets).count, 1)
    }

    func testMidnightDoesNotSplitBeforeDayStartHour() {
        // 23:50 と翌 0:03 は同じ撮影日（朝 4 時まで前日扱い）
        let assets = [makeAsset("a.raw", at: 5800, location: park), makeAsset("b.raw", at: 6600, location: park)]
        XCTAssertEqual(segmenter.segment(assets).count, 1)
    }

    func testDayStartHourSplits() {
        // 3:46 と 4:03 は別の撮影日
        let assets = [makeAsset("a.raw", at: 20000, location: park), makeAsset("b.raw", at: 21000, location: park)]
        XCTAssertEqual(segmenter.segment(assets).count, 2)
    }

    func testUndatedAssetsGoLast() {
        let assets = [makeAsset("x.raw", at: nil), makeAsset("a.raw", at: 0)]
        XCTAssertEqual(segmenter.segment(assets).map { $0.map(\.fileName) }, [["a.raw"], ["x.raw"]])
    }

    func testSameSecondIsOrderedByFileName() {
        let assets = [makeAsset("b.raw", at: 0), makeAsset("a.raw", at: 0)]
        XCTAssertEqual(segmenter.segment(assets).first?.map(\.fileName), ["a.raw", "b.raw"])
    }
}

final class RegroupingTests: XCTestCase {
    func testStricterThresholdSplitsGroupsAndKeepsIDsStable() {
        let a = makeAsset("a", at: 0), b = makeAsset("b", at: 1), c = makeAsset("c", at: 2)
        let analyses: [PhotoAsset.ID: ImageAnalysis] = [
            a.id: ImageAnalysis(featureVector: vector(angle: 0)),
            b.id: ImageAnalysis(featureVector: vector(angle: 0.1)),   // 距離 ≈ 0.10
            c.id: ImageAnalysis(featureVector: vector(angle: 0.45)),  // b との距離 ≈ 0.35
        ]
        let loose = Catalog(assets: [a.id: a, b.id: b, c.id: c], analyses: analyses).regrouped(with: .default)
        let strict = loose.regrouped(with: loose.grouping.with(similarityThreshold: 0.2))

        XCTAssertEqual(loose.scenes.flatMap(\.groups).map(\.assetIDs.count), [3])
        XCTAssertEqual(strict.scenes.flatMap(\.groups).map(\.assetIDs.count), [2, 1])
        XCTAssertEqual(strict.grouping.similarityThreshold, 0.2)
        // 先頭の写真が同じシーン・グループは ID が変わらない
        XCTAssertEqual(loose.scenes.map(\.id), strict.scenes.map(\.id))
        XCTAssertEqual(loose.scenes[0].groups[0].id, strict.scenes[0].groups[0].id)
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
        for (i, asset) in assets.enumerated() { analyses[asset.id] = ImageAnalysis(featureVector: vector(angle: Float(i) * 0.3)) }
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
