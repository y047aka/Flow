import XCTest
@testable import FlowCore

final class SceneSegmenterTests: XCTestCase {
    // baseDate は 2023-11-14 22:13:20 UTC。日付判定は UTC・朝 4 時切り替えで行う。
    let segmenter = SceneSegmenter(configuration: .init(timeZone: TimeZone(identifier: "UTC")!))

    func testSplitsOnlyByShootingDay() {
        // 撮影間隔が空いても同じ撮影日なら 1 シーン。朝 4 時を越えたら別シーン。
        let assets = [
            makeAsset("c.raw", at: 2000),
            makeAsset("a.raw", at: 0),
            makeAsset("b.raw", at: 30),
            makeAsset("d.raw", at: 21000),
        ]
        XCTAssertEqual(segmenter.segment(assets).map { $0.map(\.fileName) }, [["a.raw", "b.raw", "c.raw"], ["d.raw"]])
    }

    func testDistantLocationsOnSameDayStayTogether() {
        let tokyo = GeoCoordinate(latitude: 35.681, longitude: 139.767)
        let yokohama = GeoCoordinate(latitude: 35.466, longitude: 139.622)
        let assets = [makeAsset("a.raw", at: 0, location: tokyo), makeAsset("b.raw", at: 60, location: yokohama)]
        XCTAssertEqual(segmenter.segment(assets).count, 1)
    }

    func testMidnightDoesNotSplitBeforeDayStartHour() {
        // 23:50 と翌 0:03 は同じ撮影日（朝 4 時まで前日扱い）
        let assets = [makeAsset("a.raw", at: 5800), makeAsset("b.raw", at: 6600)]
        XCTAssertEqual(segmenter.segment(assets).count, 1)
    }

    func testDayStartHourSplits() {
        // 3:46 と 4:03 は別の撮影日
        let assets = [makeAsset("a.raw", at: 20000), makeAsset("b.raw", at: 21000)]
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
        let a = makeAsset("a", at: 0), b = makeAsset("b", at: 2), c = makeAsset("c", at: 4)
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

// 連写判定（1 秒以内）に当たらないよう、見た目の判定のテストは 2 秒間隔で並べる。
final class SimilarityClustererTests: XCTestCase {
    func testGroupsSimilarConsecutiveShots() {
        let a = makeAsset("a", at: 0), b = makeAsset("b", at: 2), c = makeAsset("c", at: 4), d = makeAsset("d", at: 6)
        let analyses: [PhotoAsset.ID: ImageAnalysis] = [
            a.id: ImageAnalysis(featureVector: vector(angle: 0)),
            b.id: ImageAnalysis(featureVector: vector(angle: 0.1)),
            c.id: ImageAnalysis(featureVector: vector(angle: 2.0)),  // 全く違う構図
            d.id: ImageAnalysis(featureVector: vector(angle: 2.05)),
        ]
        let groups = SimilarityClusterer().cluster([a, b, c, d], analyses: analyses)
        XCTAssertEqual(groups.map { $0.map(\.fileName) }, [["a", "b"], ["c", "d"]])
    }

    func testSimilarShotsJoinRegardlessOfTimeGap() {
        // 撮影間隔は問わない: 10 分空いても見た目が近ければ同じグループ
        let a = makeAsset("a", at: 0), b = makeAsset("b", at: 600)
        let analyses = [a.id: ImageAnalysis(featureVector: vector(angle: 0)), b.id: ImageAnalysis(featureVector: vector(angle: 0))]
        XCTAssertEqual(SimilarityClusterer().cluster([a, b], analyses: analyses).count, 1)
    }

    func testLinksRecordDecisions() {
        let a = makeAsset("a", at: 0), b = makeAsset("b", at: 0.5), c = makeAsset("c", at: 10), d = makeAsset("d", at: 20), e = makeAsset("e", at: 30)
        let analyses: [PhotoAsset.ID: ImageAnalysis] = [
            a.id: ImageAnalysis(featureVector: vector(angle: 0)),
            b.id: ImageAnalysis(featureVector: vector(angle: 2.0)),
            c.id: ImageAnalysis(featureVector: vector(angle: 2.1)),   // b との距離 ≈ 0.10
            d.id: ImageAnalysis(featureVector: vector(angle: 0.5)),   // 遠い
        ]
        let result = SimilarityClusterer().clusterWithLinks([a, b, c, d, e], analyses: analyses)
        XCTAssertEqual(result.links.map(\.next.fileName), ["b", "c", "d", "e"])
        XCTAssertEqual(result.links[0].decision, .burst(interval: 0.5))
        guard case .similar(let near) = result.links[1].decision else { return XCTFail("\(result.links[1].decision)") }
        XCTAssertEqual(near, 0.1, accuracy: 0.01)
        guard case .different(let far?) = result.links[2].decision else { return XCTFail("\(result.links[2].decision)") }
        XCTAssertGreaterThan(far, 0.38)
        XCTAssertEqual(result.links[3].decision, .different(distance: nil)) // 特徴ベクトルなし
        XCTAssertEqual(result.groups.map { $0.map(\.fileName) }, [["a", "b", "c"], ["d"], ["e"]])
    }

    func testMissingAnalysisMakesSingleton() {
        let a = makeAsset("a", at: 0), b = makeAsset("b", at: 2)
        let analyses = [a.id: ImageAnalysis(featureVector: vector(angle: 0))]
        XCTAssertEqual(SimilarityClusterer().cluster([a, b], analyses: analyses).count, 2)
    }

    func testComparisonWindowToleratesDrift() {
        // a→b→c と少しずつ構図が変わる（パン撮影など）。隣同士が近ければ同じグループ。
        let assets = (0..<4).map { makeAsset("p\($0)", at: TimeInterval($0 * 2)) }
        var analyses: [PhotoAsset.ID: ImageAnalysis] = [:]
        for (i, asset) in assets.enumerated() { analyses[asset.id] = ImageAnalysis(featureVector: vector(angle: Float(i) * 0.3)) }
        XCTAssertEqual(SimilarityClusterer().cluster(assets, analyses: analyses).count, 1)
    }

    // MARK: 連写

    func testBurstStaysTogetherEvenIfLooksDifferent() {
        // 動く被写体の連写: 0.2 秒間隔で見た目は大きく変わる
        let assets = (0..<5).map { makeAsset("b\($0)", at: Double($0) * 0.2, camera: "X1") }
        let analyses = Dictionary(uniqueKeysWithValues: assets.enumerated().map {
            ($1.id, ImageAnalysis(featureVector: vector(angle: Float($0) * 1.0)))
        })
        XCTAssertEqual(SimilarityClusterer().cluster(assets, analyses: analyses).count, 1)
    }

    func testBurstWithoutSubsecondsIsDetected() {
        // サブ秒を記録しないカメラ: 同じ秒は間隔 0、隣の秒は間隔 1
        let assets = [0, 0, 0, 1, 1].enumerated().map { makeAsset("b\($0)", at: TimeInterval($1)) }
        XCTAssertEqual(SimilarityClusterer().cluster(assets, analyses: [:]).count, 1)
    }

    func testGapLongerThanBurstUsesVisualSimilarity() {
        let a = makeAsset("a", at: 0), b = makeAsset("b", at: 1.5)
        let analyses = [a.id: ImageAnalysis(featureVector: vector(angle: 0)), b.id: ImageAnalysis(featureVector: vector(angle: 2.0))]
        XCTAssertEqual(SimilarityClusterer().cluster([a, b], analyses: analyses).count, 2)
    }

    // MARK: カメラの区別

    func testDifferentModelsNeverShareGroup() {
        // 2 台で交互に同じ瞬間を撮影。見た目も同じだが、カメラごとに別のグループになる。
        let assets = [
            makeAsset("a1", at: 0.0, camera: "X1"), makeAsset("b1", at: 0.1, camera: "Z9"),
            makeAsset("a2", at: 0.5, camera: "X1"), makeAsset("b2", at: 0.6, camera: "Z9"),
        ]
        let analyses = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, ImageAnalysis(featureVector: vector(angle: 0))) })
        let groups = SimilarityClusterer().cluster(assets, analyses: analyses)
        // 各カメラの写真は交互に挟まれていても 1 つにまとまり、グループは先頭の写真の撮影順に並ぶ
        XCTAssertEqual(groups.map { $0.map(\.fileName) }, [["a1", "a2"], ["b1", "b2"]])
    }

    func testSerialNumberDistinguishesBodiesOfSameModel() {
        let assets = [
            makeAsset("a1", at: 0.0, camera: "X1", serial: "111"),
            makeAsset("b1", at: 0.1, camera: "X1", serial: "222"),
            makeAsset("a2", at: 0.2, camera: "X1", serial: "111"),
        ]
        let groups = SimilarityClusterer().cluster(assets, analyses: [:])
        XCTAssertEqual(groups.map { $0.map(\.fileName) }, [["a1", "a2"], ["b1"]])
    }

    func testSameModelWithoutSerialIsTreatedAsOneCamera() {
        // シリアル番号が無ければ機種で識別するので、同じ機種 2 台の同時撮影は区別できない（許容）
        let assets = [makeAsset("a1", at: 0.0, camera: "X1"), makeAsset("b1", at: 0.1, camera: "X1")]
        XCTAssertEqual(SimilarityClusterer().cluster(assets, analyses: [:]).count, 1)
    }
}

final class CameraIdentityTests: XCTestCase {
    func testIdentityPrefersSerialNumber() {
        XCTAssertEqual(CaptureMetadata(cameraMake: "Maker", cameraModel: "X1", cameraSerialNumber: " 123 ").cameraIdentity,
                       .body(make: "Maker", model: "X1", serialNumber: "123"))
        XCTAssertEqual(CaptureMetadata(cameraMake: "Maker", cameraModel: "X1", cameraSerialNumber: "").cameraIdentity,
                       .model(make: "Maker", model: "X1"))
        XCTAssertNil(CaptureMetadata().cameraIdentity)
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

final class LinksBySceneTests: XCTestCase {
    func testLinksBySceneListsConsecutivePairsPerScene() {
        let assets = [makeAsset("a", at: 0), makeAsset("b", at: 2), makeAsset("c", at: 4), makeAsset("d", at: 86_400)]
        let catalog = Catalog(assets: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })).regrouped(with: .default)
        let links = catalog.linksByScene
        XCTAssertEqual(catalog.scenes.count, 2)
        XCTAssertEqual(links[catalog.scenes[0].id]?.map(\.next.fileName), ["b", "c"])
        XCTAssertEqual(links[catalog.scenes[1].id]?.isEmpty, true)
        XCTAssertEqual(links[catalog.scenes[0].id]?.map(\.id), [assets[1].id, assets[2].id])
    }
}
