#if canImport(Vision)
import CoreGraphics
import FlowCore
import Foundation
import Vision

/// Vision フレームワークで類似度・美しさ・顔の写り・シャープネスを解析する。
public struct VisionImageAnalyzer: ImageAnalyzing {
    public let previewLoader: PreviewImageLoader

    public init(previewLoader: PreviewImageLoader = .init(maximumPixelSize: 1024)) {
        self.previewLoader = previewLoader
    }

    public func analyze(_ asset: PhotoAsset) async throws -> ImageAnalysis {
        let image = try previewLoader.loadPreview(at: asset.fileURL)
        try Task.checkCancellation()
        return Self.analyze(image)
    }

    /// 各指標を独立に求めて 1 つの解析結果にまとめる。1 つが失敗しても他の結果は残る。
    public static func analyze(_ image: CGImage) -> ImageAnalysis {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        let aesthetics = aestheticsScores(handler)
        let faceQualities = faceCaptureQualities(handler)
        return ImageAnalysis(
            featureVector: featurePrint(handler),
            tileFeatureVectors: tileFeaturePrints(image),
            aestheticsScore: aesthetics?.overallScore,
            isUtility: aesthetics?.isUtility,
            sharpness: GrayscaleBuffer(image: image, maximumDimension: 1024)?.normalizedSharpness(),
            faceCount: faceQualities.count,
            minimumFaceQuality: faceQualities.compactMap { $0 }.min()
        )
    }

    // MARK: - 個々の指標

    static func featurePrint(_ handler: VNImageRequestHandler) -> FeatureVector? {
        let request = VNGenerateImageFeaturePrintRequest()
        // OS バージョンが変わってもベクトルの互換性を保つため、リビジョンを固定する。
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        return perform(request, on: handler)?.results?.first.map { FeatureVector(floats(from: $0)) }
    }

    /// 画像を 2×2 に分けた領域ごとの特徴ベクトル（左上・右上・左下・右下）。1 つでも取れなければ nil。
    /// プレビューは回転を適用済みなので、写真の向きに関係なく同じ位置の領域どうしを比べられる。
    static func tileFeaturePrints(_ image: CGImage, rows: Int = 2, columns: Int = 2) -> [FeatureVector]? {
        let tileWidth = image.width / columns
        let tileHeight = image.height / rows
        guard tileWidth > 0, tileHeight > 0 else { return nil }
        let vectors = (0..<rows).flatMap { row in
            (0..<columns).map { column in
                // CGImage の切り抜きは左上が原点
                image.cropping(to: CGRect(x: column * tileWidth, y: row * tileHeight, width: tileWidth, height: tileHeight))
                    .flatMap { featurePrint(VNImageRequestHandler(cgImage: $0, orientation: .up, options: [:])) }
            }
        }
        let complete = vectors.compactMap { $0 }
        return complete.count == rows * columns ? complete : nil
    }

    static func aestheticsScores(_ handler: VNImageRequestHandler) -> VNImageAestheticsScoresObservation? {
        perform(VNCalculateImageAestheticsScoresRequest(), on: handler)?.results?.first
    }

    /// 検出された顔ごとの写りの品質（取得できない顔は nil）。
    static func faceCaptureQualities(_ handler: VNImageRequestHandler) -> [Float?] {
        (perform(VNDetectFaceCaptureQualityRequest(), on: handler)?.results ?? [])
            .map { floatValue($0.faceCaptureQuality) }
    }

    /// リクエストを実行し、成功すれば結果を保持したリクエストを返す。
    static func perform<Request: VNRequest>(_ request: Request, on handler: VNImageRequestHandler) -> Request? {
        (try? handler.perform([request])).map { request }
    }

    static func floats(from observation: VNFeaturePrintObservation) -> [Float] {
        let data = observation.data
        switch observation.elementType {
        case .float: return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        case .double: return data.withUnsafeBytes { $0.bindMemory(to: Double.self).map(Float.init) }
        default: return []
        }
    }
}

// faceCaptureQuality は SDK によって Float? / NSNumber? のどちらでも受けられるようにする。
private func floatValue(_ value: Float?) -> Float? { value }
private func floatValue(_ value: NSNumber?) -> Float? { value?.floatValue }
#endif
