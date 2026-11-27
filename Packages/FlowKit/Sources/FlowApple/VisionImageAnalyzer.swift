#if canImport(Vision)
import CoreGraphics
import FlowCore
import Foundation
import Vision

/// Vision フレームワークで類似度・美しさ・顔の写り・シャープネスを解析する。
public struct VisionImageAnalyzer: ImageAnalyzing {
    public var previewLoader: PreviewImageLoader

    public init(previewLoader: PreviewImageLoader = .init(maximumPixelSize: 1024)) {
        self.previewLoader = previewLoader
    }

    public func analyze(_ asset: PhotoAsset) async throws -> ImageAnalysis {
        let image = try previewLoader.loadPreview(at: asset.fileURL)
        try Task.checkCancellation()
        return Self.analyze(image)
    }

    /// 各リクエストは独立して実行し、1 つが失敗しても他の結果は残す。
    public static func analyze(_ image: CGImage) -> ImageAnalysis {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        var analysis = ImageAnalysis()

        let featureRequest = VNGenerateImageFeaturePrintRequest()
        // OS バージョンが変わってもベクトルの互換性を保つため、リビジョンを固定する。
        featureRequest.revision = VNGenerateImageFeaturePrintRequestRevision2
        if (try? handler.perform([featureRequest])) != nil, let observation = featureRequest.results?.first {
            analysis.featureVector = FeatureVector(floats(from: observation))
        }

        let aestheticsRequest = VNCalculateImageAestheticsScoresRequest()
        if (try? handler.perform([aestheticsRequest])) != nil, let observation = aestheticsRequest.results?.first {
            analysis.aestheticsScore = observation.overallScore
            analysis.isUtility = observation.isUtility
        }

        let faceRequest = VNDetectFaceCaptureQualityRequest()
        if (try? handler.perform([faceRequest])) != nil, let faces = faceRequest.results {
            analysis.faceCount = faces.count
            analysis.minimumFaceQuality = faces.compactMap { floatValue($0.faceCaptureQuality) }.min()
        }

        if let gray = GrayscaleBuffer(image: image, maximumDimension: 1024) {
            analysis.sharpness = gray.normalizedSharpness()
        }
        return analysis
    }

    static func floats(from observation: VNFeaturePrintObservation) -> [Float] {
        let data = observation.data
        switch observation.elementType {
        case .float:
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        case .double:
            return data.withUnsafeBytes { $0.bindMemory(to: Double.self).map { Float($0) } }
        default:
            return []
        }
    }
}

// faceCaptureQuality は SDK によって Float? / NSNumber? のどちらでも受けられるようにする。
private func floatValue(_ value: Float?) -> Float? { value }
private func floatValue(_ value: NSNumber?) -> Float? { value?.floatValue }
#endif
