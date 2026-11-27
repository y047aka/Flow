import Foundation

/// 撮影時刻の連続性で区切られた「シーン」。
public struct PhotoScene: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let startDate: Date?
    public let endDate: Date?
    public let groups: [SimilarGroup]

    public init(id: UUID = UUID(), startDate: Date?, endDate: Date?, groups: [SimilarGroup]) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.groups = groups
    }

    public var assetIDs: [PhotoAsset.ID] { groups.flatMap(\.assetIDs) }
}

/// 連写・構図違いなど、似たショットのまとまり。
public struct SimilarGroup: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// 撮影順に並んだメンバー。
    public let assetIDs: [PhotoAsset.ID]
    /// 自動選定されたベストショット。
    public let bestAssetID: PhotoAsset.ID?

    public init(id: UUID = UUID(), assetIDs: [PhotoAsset.ID], bestAssetID: PhotoAsset.ID? = nil) {
        self.id = id
        self.assetIDs = assetIDs
        self.bestAssetID = bestAssetID
    }
}

/// 1 回の取り込み（=1 つのフォルダ / カード）の全情報。JSON でそのまま保存できる。
/// 不変の値で、変更は `with…` / `regrouped` で新しいカタログを作って行う。
public struct Catalog: Codable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let assets: [PhotoAsset.ID: PhotoAsset]
    public let analyses: [PhotoAsset.ID: ImageAnalysis]
    /// 写真ごとの自動推定レシピ（プリセット適用前）。
    public let autoRecipes: [PhotoAsset.ID: DevelopRecipe]
    public let scenes: [PhotoScene]
    public let presetID: DevelopPreset.ID
    /// 取り込み元フォルダの（セキュリティスコープ付き）ブックマーク。再起動後のアクセス復元に使う。
    public let sourceFolderBookmark: Data?
    /// グルーピングの設定。古いカタログには無いので省略可能。
    public let groupingSettings: GroupingSettings?

    public init(
        assets: [PhotoAsset.ID: PhotoAsset] = [:],
        analyses: [PhotoAsset.ID: ImageAnalysis] = [:],
        autoRecipes: [PhotoAsset.ID: DevelopRecipe] = [:],
        scenes: [PhotoScene] = [],
        presetID: DevelopPreset.ID = DevelopPreset.neutral.id,
        sourceFolderBookmark: Data? = nil,
        groupingSettings: GroupingSettings? = nil
    ) {
        self.version = Self.currentVersion
        self.assets = assets
        self.analyses = analyses
        self.autoRecipes = autoRecipes
        self.scenes = scenes
        self.presetID = presetID
        self.sourceFolderBookmark = sourceFolderBookmark
        self.groupingSettings = groupingSettings
    }

    // MARK: - 派生値

    /// 現在のグルーピング設定（未設定なら既定値）。
    public var grouping: GroupingSettings { groupingSettings ?? .default }

    public var preset: DevelopPreset {
        DevelopPreset.builtIn.first { $0.id == presetID } ?? .neutral
    }

    /// 自動レシピに現在のプリセットを重ねた、最終的な現像レシピ。
    public func recipe(for assetID: PhotoAsset.ID) -> DevelopRecipe {
        preset.apply(to: autoRecipes[assetID] ?? DevelopRecipe())
    }

    /// 各グループのベストショット（書き出し候補）。
    public var bestAssets: [PhotoAsset] {
        scenes.flatMap(\.groups).compactMap { $0.bestAssetID.flatMap { assets[$0] } }
    }

    // MARK: - 新しいカタログを作る

    public func with(presetID: DevelopPreset.ID) -> Catalog {
        copy(presetID: presetID)
    }

    public func with(sourceFolderBookmark: Data?) -> Catalog {
        copy(sourceFolderBookmark: .some(sourceFolderBookmark))
    }

    /// 解析をやり直さずに、別の設定でグルーピングし直したカタログ。数百枚なら数ミリ秒で終わる。
    public func regrouped(with settings: GroupingSettings) -> Catalog {
        copy(scenes: settings.grouper.group(Array(assets.values), analyses: analyses), groupingSettings: settings)
    }

    private func copy(
        scenes: [PhotoScene]? = nil,
        presetID: DevelopPreset.ID? = nil,
        sourceFolderBookmark: Data?? = nil,
        groupingSettings: GroupingSettings? = nil
    ) -> Catalog {
        Catalog(
            assets: assets,
            analyses: analyses,
            autoRecipes: autoRecipes,
            scenes: scenes ?? self.scenes,
            presetID: presetID ?? self.presetID,
            sourceFolderBookmark: sourceFolderBookmark ?? self.sourceFolderBookmark,
            groupingSettings: groupingSettings ?? self.groupingSettings
        )
    }
}
