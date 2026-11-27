import Foundation

public enum FlowAppleError: Error, LocalizedError {
    case cannotOpen(URL)
    case noPreview(URL)
    case unsupportedRAW(URL)
    case renderFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let url): "ファイルを開けません: \(url.lastPathComponent)"
        case .noPreview(let url): "プレビュー画像を取り出せません: \(url.lastPathComponent)"
        case .unsupportedRAW(let url): "この RAW 形式（カメラ機種）は OS が未対応です: \(url.lastPathComponent)"
        case .renderFailed(let url): "現像に失敗しました: \(url.lastPathComponent)"
        }
    }
}
