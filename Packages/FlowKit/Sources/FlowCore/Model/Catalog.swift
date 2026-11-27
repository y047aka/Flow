import Foundation

/// 撮影時刻の連続性で区切られた「シーン」。
public struct PhotoScene: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var startDate: Date?
    public var endDate: Date?
    public var groups: [SimilarGroup]

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
    public var id: UUID
    /// 撮影順に並んだメンバー。
    public var assetIDs: [PhotoAsset.ID]
    /// 自動選定されたベストショット。
    public var bestAssetID: PhotoAsset.ID?

    public init(id: UUID = UUID(), assetIDs: [PhotoAsset.ID], bestAssetID: PhotoAsset.ID? = nil) {
        self.id = id
        self.assetIDs = assetIDs
        self.bestAssetID = bestAssetID
    }
}

/// 1 回の取り込み（=1 つのフォルダ / カード）の全情報。JSON でそのまま保存できる。
public struct Catalog: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var assets: [PhotoAsset.ID: PhotoAsset]
    public var analyses: [PhotoAsset.ID: ImageAnalysis]
    /// 写真ごとの自動推定レシピ（プリセット適用前）。
    public var autoRecipes: [PhotoAsset.ID: DevelopRecipe]
    public var scenes: [PhotoScene]
    public var presetID: DevelopPreset.ID
    /// 取り込み元フォルダの（セキュリティスコープ付き）ブックマーク。再起動後のアクセス復元に使う。
    public var sourceFolderBookmark: Data?

    public init(
        assets: [PhotoAsset.ID: PhotoAsset] = [:],
        analyses: [PhotoAsset.ID: ImageAnalysis] = [:],
        autoRecipes: [PhotoAsset.ID: DevelopRecipe] = [:],
        scenes: [PhotoScene] = [],
        presetID: DevelopPreset.ID = DevelopPreset.neutral.id
    ) {
        self.version = Self.currentVersion
        self.assets = assets
        self.analyses = analyses
        self.autoRecipes = autoRecipes
        self.scenes = scenes
        self.presetID = presetID
    }

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
}
