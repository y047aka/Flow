#if canImport(ImageIO)
import FlowCore
import Foundation
import ImageIO

/// ImageIO で EXIF / TIFF / GPS を読む。RAW 本体はデコードしないので高速。
public struct ImageIOMetadataReader: MetadataReading {
    public init() {}

    public func readMetadata(at url: URL) throws -> CaptureMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw FlowAppleError.cannotOpen(url)
        }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]

        return CaptureMetadata(
            captureDate: Self.captureDate(exif: exif, tiff: tiff),
            cameraMake: tiff[kCGImagePropertyTIFFMake] as? String,
            cameraModel: tiff[kCGImagePropertyTIFFModel] as? String,
            lensModel: exif[kCGImagePropertyExifLensModel] as? String,
            focalLength: exif[kCGImagePropertyExifFocalLength] as? Double,
            fNumber: exif[kCGImagePropertyExifFNumber] as? Double,
            exposureTime: exif[kCGImagePropertyExifExposureTime] as? Double,
            iso: (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first,
            pixelWidth: props[kCGImagePropertyPixelWidth] as? Int,
            pixelHeight: props[kCGImagePropertyPixelHeight] as? Int,
            location: gps.flatMap(Self.coordinate)
        )
    }

    static func captureDate(exif: [CFString: Any], tiff: [CFString: Any]) -> Date? {
        guard let string = exif[kCGImagePropertyExifDateTimeOriginal] as? String
                ?? tiff[kCGImagePropertyTIFFDateTime] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        // EXIF 2.31 のタイムゾーン（例: "+09:00"）があれば使い、無ければ端末のタイムゾーンとみなす。
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String, let tz = Self.timeZone(fromOffset: offset) {
            formatter.timeZone = tz
        } else {
            formatter.timeZone = .current
        }
        guard var date = formatter.date(from: string) else { return nil }
        // 連写の順序を保つためにサブ秒も加える。
        if let subsec = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, let value = Double("0." + subsec) {
            date.addTimeInterval(value)
        }
        return date
    }

    static func timeZone(fromOffset offset: String) -> TimeZone? {
        let sign: Int = offset.hasPrefix("-") ? -1 : 1
        let parts = offset.trimmingCharacters(in: CharacterSet(charactersIn: "+-")).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return TimeZone(secondsFromGMT: sign * (h * 3600 + m * 60))
    }

    static func coordinate(gps: [CFString: Any]) -> GeoCoordinate? {
        guard var lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              var lon = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
        return GeoCoordinate(latitude: lat, longitude: lon)
    }
}
#endif
