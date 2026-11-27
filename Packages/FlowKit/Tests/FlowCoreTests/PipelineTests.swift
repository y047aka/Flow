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
        let files = ["0_0.0", "1_0.1", "2_2.0", "3000_2.0", "broken_0"].map { URL(fileURLWithPath: "/card/\($0).raw") }
        let pipeline = LibraryPipeline(
            metadataReader: FakeMetadataReader(),
            analyzer: FakeAnalyzer(),
            toneMeasurer: FakeToneMeasurer(),
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
        XCTAssertGreaterThan(result.catalog.recipe(for: firstGroup.bestAssetID!).exposure, 0)
        XCTAssertEqual(Set(stages.values), [.readingMetadata, .analyzing, .estimatingTone, .grouping])
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
