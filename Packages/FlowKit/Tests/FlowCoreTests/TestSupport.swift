import Foundation
@testable import FlowCore

let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

func makeAsset(_ name: String, at seconds: TimeInterval?, location: GeoCoordinate? = nil) -> PhotoAsset {
    PhotoAsset(
        fileURL: URL(fileURLWithPath: "/photos/\(name)"),
        metadata: CaptureMetadata(captureDate: seconds.map { baseDate.addingTimeInterval($0) }, location: location)
    )
}

/// 単位ベクトルを角度で作る（距離 = 2·sin(θ/2)）。
func vector(angle: Float) -> FeatureVector {
    FeatureVector([cos(angle), sin(angle)])
}
