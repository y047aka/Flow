import Foundation

/// 取り込み → 解析 → グルーピング → 自動補正推定 を一括で行う。
public struct LibraryPipeline: Sendable {
    public enum Stage: String, Sendable {
        case readingMetadata
        case analyzing
        case estimatingTone
        case grouping
    }

    public struct ProgressUpdate: Sendable {
        public var stage: Stage
        public var completed: Int
        public var total: Int
    }

    public struct Result: Sendable {
        public var catalog: Catalog
        /// 読み込めなかったファイルと理由。
        public var failures: [URL: String]
    }

    public var metadataReader: any MetadataReading
    public var analyzer: any ImageAnalyzing
    public var toneMeasurer: any ToneMeasuring
    public var grouper: CatalogGrouper
    public var toneEstimator: AutoToneEstimator
    /// 同時に処理する枚数。iPad ではメモリを考慮して小さめにする。
    public var maximumConcurrency: Int

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
        progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in }
    ) async throws -> Result {
        var failures: [URL: String] = [:]

        // 1. メタデータ
        let reader = metadataReader
        let read = try await files.concurrentMap(maximumConcurrency, stage: .readingMetadata, progress: progress) { url in
            PhotoAsset(fileURL: url, bookmarkData: bookmark(url), metadata: try reader.readMetadata(at: url))
        }
        var assets: [PhotoAsset] = []
        for (url, result) in zip(files, read) {
            switch result {
            case .success(let asset): assets.append(asset)
            case .failure(let error): failures[url] = String(describing: error)
            }
        }

        // 2. 画像解析（失敗しても写真自体はカタログに残す）
        let analyzer = self.analyzer
        let analysisResults = try await assets.concurrentMap(maximumConcurrency, stage: .analyzing, progress: progress) {
            try await analyzer.analyze($0)
        }
        var analyses: [PhotoAsset.ID: ImageAnalysis] = [:]
        for (asset, result) in zip(assets, analysisResults) {
            if case .success(let analysis) = result { analyses[asset.id] = analysis }
        }

        // 3. 自動補正の推定
        let measurer = toneMeasurer
        let estimator = toneEstimator
        let toneResults = try await assets.concurrentMap(maximumConcurrency, stage: .estimatingTone, progress: progress) {
            estimator.estimate(from: try await measurer.luminanceHistogram(for: $0))
        }
        var recipes: [PhotoAsset.ID: DevelopRecipe] = [:]
        for (asset, result) in zip(assets, toneResults) {
            if case .success(let recipe) = result { recipes[asset.id] = recipe }
        }

        // 4. グルーピング
        progress(.init(stage: .grouping, completed: 0, total: 1))
        let scenes = grouper.group(assets, analyses: analyses)
        progress(.init(stage: .grouping, completed: 1, total: 1))

        let catalog = Catalog(
            assets: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }),
            analyses: analyses,
            autoRecipes: recipes,
            scenes: scenes
        )
        return Result(catalog: catalog, failures: failures)
    }
}

extension Array where Element: Sendable {
    /// 同時実行数を制限した並列 map。結果は入力と同じ順序。個々の失敗は Result として返し、キャンセルのみ throw する。
    func concurrentMap<T: Sendable>(
        _ maximumConcurrency: Int,
        stage: LibraryPipeline.Stage,
        progress: @escaping @Sendable (LibraryPipeline.ProgressUpdate) -> Void,
        _ transform: @escaping @Sendable (Element) async throws -> T
    ) async throws -> [Swift.Result<T, Error>] {
        var results = [Swift.Result<T, Error>?](repeating: nil, count: count)
        var completed = 0
        progress(.init(stage: stage, completed: 0, total: count))

        try await withThrowingTaskGroup(of: (Int, Swift.Result<T, Error>).self) { group in
            var next = 0
            func addNext() {
                let index = next
                let element = self[index]
                group.addTask {
                    do { return (index, .success(try await transform(element))) }
                    catch { return (index, .failure(error)) }
                }
                next += 1
            }
            while next < Swift.min(maximumConcurrency, count) { addNext() }
            while let (index, result) = try await group.next() {
                try Task.checkCancellation()
                results[index] = result
                completed += 1
                progress(.init(stage: stage, completed: completed, total: count))
                if next < count { addNext() }
            }
        }
        return results.map { $0! }
    }
}
