# Flow

デジタル一眼の RAW を数百枚まとめて取り込み、**自動で整理・グループ分け・ベストショット選定・クセのない現像**を行う macOS / iPad アプリ。
細かな現像パラメータの GUI は持たず、ユーザーが選ぶのはプリセットだけ。

## 必要環境

- macOS 15 以降 + Xcode 16 以降
- 実行対象: macOS 15+ / iPadOS 18+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（Xcode プロジェクト生成用）

## セットアップ

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open Flow.xcodeproj
```

スキーム `Flow` を選び、実行先を「My Mac」または iPad シミュレータ / 実機にして実行する。
実機で動かす場合は `project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` と `DEVELOPMENT_TEAM` を自分のものに変更する。

`Flow.xcodeproj` は生成物なのでコミットしない（`.gitignore` 済み）。設定変更は `project.yml` に対して行い、再生成する。

### コアロジックのテスト

`FlowCore` は Foundation のみに依存するので、Xcode なしでも（Linux でも）テストできる。

```bash
swift test --package-path Packages/FlowKit
```

## 構成

```
Flow/
├── project.yml                 XcodeGen 設定（macOS + iPad の単一マルチプラットフォームターゲット）
├── App/                        SwiftUI アプリ（UI と状態管理のみ）
│   ├── FlowApp.swift
│   ├── AppModel.swift          取り込み・プリセット・書き出しの状態管理
│   ├── ThumbnailProvider.swift
│   └── Views/
└── Packages/FlowKit/           ロジック本体（Swift Package）
    ├── Sources/FlowCore/       プラットフォーム非依存
    │   ├── Model/              PhotoAsset, Catalog, ImageAnalysis …
    │   ├── Grouping/           シーン分割・類似クラスタリング・ベストショット選定
    │   ├── Develop/            現像レシピ・プリセット・自動補正推定
    │   └── Pipeline/           処理パイプライン・サービスのプロトコル・保存
    ├── Sources/FlowApple/      Apple 専用実装
    │   ├── ImageIOMetadataReader.swift   EXIF / GPS
    │   ├── PreviewImageLoader.swift      RAW 埋め込みプレビューの高速抽出
    │   ├── VisionImageAnalyzer.swift     類似度・美しさ・顔の写り・シャープネス
    │   └── CoreImageRAWDeveloper.swift   CIRAWFilter による現像と書き出し
    └── Tests/FlowCoreTests/
```

### 層の分け方

- **FlowCore** は `MetadataReading` / `ImageAnalyzing` / `ToneMeasuring` / `PhotoExporting` プロトコルと、それらを使うアルゴリズムだけを持つ。
- **FlowApple** がそのプロトコルを ImageIO / Vision / Core Image で実装する。
- Windows 版を作るときは FlowCore をそのまま使い、プロトコルを LibRaw・ONNX Runtime などで実装し直す。

### コーディング方針（関数型のコア＋命令型の外殻）

- **値は不変**：モデル（`PhotoAsset`、`Catalog`、`DevelopRecipe` など）のプロパティは `let`。
  変更は `catalog.with(presetID:)` や `catalog.regrouped(by:)` のように、新しい値を返す関数で表す。
- **ロジックは純粋関数**：グループ分けやスコア計算は `map` / `filter` / `reduce` と、
  `Functional.swift` の汎用ヘルパー（`chunked(by:)`、`grouped(while:)`、`cumulativeSums()` など）で書く。
- **現像は関数の合成**：レシピから `CIImage -> CIImage` の調整関数の列を作り、`reduce` で順に適用する。
- **手続き的に書く箇所（理由付き）**：
  - UI 状態とファイル入出力（`AppModel`）：副作用の実行そのもの。書き出し内容の決定（`exportJobs`）は純粋関数に分けてある。
  - `CIRAWFilter` の設定：API がプロパティを書き換える形のため、1 つの関数に閉じ込めた。
  - `concurrentMap` の内部：同時実行数を制限するスライディングウィンドウは、TaskGroup の手続き的な操作でしか書けない。
  - `GrayscaleBuffer.laplacianVariance`：画素ごとの最も重いループなので性能を優先した。

## 処理の流れ

```
フォルダ選択
 └ RawFileScanner          RAW ファイルを再帰的に列挙
    └ LibraryPipeline
       1. メタデータ        ImageIO で EXIF（撮影日時・サブ秒・タイムゾーン・GPS・レンズ）
       2. 画像解析          埋め込みプレビュー（1024px）に Vision を適用
                             - FeaturePrint（類似度、revision 2 で固定）
                             - Aesthetics スコア / isUtility
                             - 顔の写り品質（目つむり・ブレ）
                             - ラプラシアン分散によるシャープネス
       3. 自動補正推定      中立現像の縮小画像のヒストグラムから露出・ハイライト・シャドウのみ穏やかに補正
       4. グルーピング      SceneSegmenter → SimilarityClusterer → BestShotSelector
 └ Catalog（JSON 保存）    元 RAW + 非破壊レシピ。プリセットは表示時・書き出し時に重ねる
```

- 重い解析は RAW のフルデコードを避け、埋め込みプレビューで行う。
- RAW のフルデコードは、プレビュー表示（表示サイズに縮小）と書き出しのときだけ行う。
- 最終的な現像結果は「自動推定レシピ」に「プリセット」を重ねたもの（`Catalog.recipe(for:)`）。プリセットを替えても再解析は不要。

## 調整が必要な値

実際の写真で確かめて調整する値。

| 値 | 場所 | 初期値 |
|---|---|---|
| シーン区切りの撮影間隔 | `SceneSegmenter.Configuration.maximumTimeGap` | 15 分 |
| シーン区切りの距離 | `SceneSegmenter.Configuration.maximumDistance` | 500 m |
| 類似とみなす特徴ベクトル距離 | `SimilarityClusterer.Configuration.maximumDistance` | 0.55 |
| ベストショットの重み | `BestShotSelector.Weights` | 美しさ 1.0 / シャープネス 1.0 / 顔 1.5 |
| 自動露出の強さ・上限 | `AutoToneEstimator.Configuration` | 60% / ±1EV |
| シャープネスの正規化 | `GrayscaleBuffer.normalizedSharpness(halfPoint:)` | 300 |

## 今後の作業

- [ ] 書き出しファイルへの EXIF / GPS コピー
- [ ] コントラスト調整を知覚的なトーンカーブに置き換え
- [ ] シャープネスを主要被写体（顔・注目領域）の切り抜きで測る
- [ ] `ImageCaptureCore` によるカメラ・SD カードからの直接取り込み
- [ ] 取り込みの途中経過の保存と再開、キャンセル UI
- [ ] グループの手動修正（分割・統合・ベスト変更）
- [ ] カタログが大きくなったら SQLite（GRDB など）へ移行
- [ ] OS が未対応のカメラ機種向けの案内（DNG 変換）
