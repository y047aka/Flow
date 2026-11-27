import Foundation

/// 取り込み → 解析 → 自動補正推定 → グルーピング を一括で行う。
///
/// 各段は「全写真に並列で関数を適用し（`concurrentMap`）、成功した結果だけを集める」という同じ形をしている。
public struct LibraryPipeline: Sendable {
    public enum Stage: String, Sendable {
        case readingMetadata
        case analyzing
        case estimatingTone
        case grouping
    }

    public struct ProgressUpdate: Sendable {
        public let stage: Stage
        public let completed: Int
        public let total: Int
    }

    public struct Result: Sendable {
        public let catalog: Catalog
        /// 読み込めなかったファイルと理由。
        public let failures: [URL: String]
    }

    public typealias ProgressHandler = @Sendable (ProgressUpdate) -> Void

    public let metadataReader: any MetadataReading
    public let analyzer: any ImageAnalyzing
    public let toneMeasurer: any ToneMeasuring
    public let grouper: CatalogGrouper
    public let toneEstimator: AutoToneEstimator
    /// 同時に処理する枚数。iPad ではメモリを考慮して小さめにする。
    public let maximumConcurrency: Int

    public init(
        metadataReader: any MetadataReading,
        analyzer: any ImageAnalyzing,
        toneMeasurer: any ToneMeasuring,
        grouper: CatalogGrouper = .init(),
        toneEstimator: AutoToneEstimator = .init(),
        maximumConcurrency: Int = 4
    ) {
        self.metadataReader = metadataReader
        self.analyzer = analyzer
        self.toneMeasurer = toneMeasurer
        self.grouper = grouper
        self.toneEstimator = toneEstimator
        self.maximumConcurrency = max(1, maximumConcurrency)
    }

    public func run(
        files: [URL],
        bookmark: @escaping @Sendable (URL) -> Data? = { _ in nil },
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> Result {
        let (reader, analyzer, measurer, estimator) = (metadataReader, self.analyzer, toneMeasurer, toneEstimator)

        // 1. メタデータ（読めなかったファイルは failures へ）
        let read = try await files.concurrentMap(maximumConcurrency, stage: .readingMetadata, progress: progress) { url in
            PhotoAsset(fileURL: url, bookmarkData: bookmark(url), metadata: try reader.readMetadata(at: url))
        }
        let assets = read.compactMap { $0.1.success }

        // 2. 画像解析 / 3. 自動補正の推定（失敗しても写真自体はカタログに残す）
        let analyses = successes(
            try await assets.concurrentMap(maximumConcurrency, stage: .analyzing, progress: progress) {
                try await analyzer.analyze($0)
            },
            keyedBy: \.id
        )
        let recipes = successes(
            try await assets.concurrentMap(maximumConcurrency, stage: .estimatingTone, progress: progress) {
                estimator.estimate(from: try await measurer.luminanceHistogram(for: $0))
            },
            keyedBy: \.id
        )

        // 4. グルーピング
        progress(.init(stage: .grouping, completed: 0, total: 1))
        let scenes = grouper.group(assets, analyses: analyses)
        progress(.init(stage: .grouping, completed: 1, total: 1))

        return Result(
            catalog: Catalog(
                assets: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }),
                analyses: analyses,
                autoRecipes: recipes,
                scenes: scenes
            ),
            failures: failures(read, keyedBy: { $0 }).mapValues { String(describing: $0) }
        )
    }
}

extension Array where Element: Sendable {
    /// 同時実行数を制限した並列 map。入力と同じ順序で (入力, 結果) の組を返す。
    /// 個々の失敗は Result として返し、キャンセルのみ throw する。
    ///
    /// 「常に最大 N 件を実行中に保つ」スライディングウィンドウは TaskGroup の命令的な操作でしか表現できないため、
    /// この関数の内部だけは手続き的に書いている（外から見ると純粋な map として使える）。
    func concurrentMap<T: Sendable>(
        _ maximumConcurrency: Int,
        stage: LibraryPipeline.Stage,
        progress: @escaping LibraryPipeline.ProgressHandler,
        _ transform: @escaping @Sendable (Element) async throws -> T
    ) async throws -> [(Element, Swift.Result<T, Error>)] {
        progress(.init(stage: stage, completed: 0, total: count))

        let results = try await withThrowingTaskGroup(of: (Int, Swift.Result<T, Error>).self) { group in
            var pending = self.indices.makeIterator()
            func addNext() {
                guard let index = pending.next() else { return }
                let element = self[index]
                group.addTask {
                    do { return (index, .success(try await transform(element))) }
                    catch { return (index, .failure(error)) }
                }
            }
            (0..<Swift.min(maximumConcurrency, count)).forEach { _ in addNext() }

            var collected: [Int: Swift.Result<T, Error>] = [:]
            while let (index, result) = try await group.next() {
                try Task.checkCancellation()
                collected[index] = result
                progress(.init(stage: stage, completed: collected.count, total: count))
                addNext()
            }
            return collected
        }
        return indices.map { (self[$0], results[$0]!) }
    }
}
