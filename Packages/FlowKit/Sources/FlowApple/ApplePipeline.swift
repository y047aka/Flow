#if canImport(CoreImage) && canImport(Vision)
import FlowCore
import Foundation

public extension LibraryPipeline {
    /// Apple 純正フレームワークで構成したパイプライン。
    static func apple(developer: CoreImageRAWDeveloper, maximumConcurrency: Int? = nil) -> LibraryPipeline {
        LibraryPipeline(
            metadataReader: ImageIOMetadataReader(),
            analyzer: VisionImageAnalyzer(),
            toneMeasurer: developer,
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
#endif
