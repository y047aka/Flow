#if canImport(CoreImage) && canImport(Vision)
import FlowCore
import Foundation

public extension LibraryPipeline {
    /// Apple 純正フレームワークで構成したパイプライン。
    static func apple(maximumConcurrency: Int? = nil) -> LibraryPipeline {
        LibraryPipeline(
            metadataReader: ImageIOMetadataReader(),
            analyzer: VisionImageAnalyzer(),
            maximumConcurrency: maximumConcurrency ?? defaultConcurrency
        )
    }

    /// iPad はメモリ上限が厳しいため、Mac より同時実行数を抑える。
    static var defaultConcurrency: Int {
        #if os(iOS)
        return 2
        #else
        return max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2))
        #endif
    }
}

public extension AutoToneService {
    /// CIRAWFilter の中立現像で明るさを測る自動補正サービス。
    static func apple(developer: CoreImageRAWDeveloper) -> AutoToneService {
        AutoToneService(measurer: developer)
    }

    /// 裏で自動補正を計算する同時実行数。RAW の現像は GPU を使うので、
    /// 画面のプレビュー現像を妨げないよう取り込み時の半分程度に抑える。
    static var backgroundConcurrency: Int {
        max(1, LibraryPipeline.defaultConcurrency / 2)
    }
}
#endif
