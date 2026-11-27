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
        let exifAux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        return CaptureMetadata(
            captureDate: Self.captureDate(exif: exif, tiff: tiff),
            cameraMake: tiff[kCGImagePropertyTIFFMake] as? String,
            cameraModel: tiff[kCGImagePropertyTIFFModel] as? String,
            // EXIF 2.3 の BodySerialNumber を優先し、無ければ ExifAux（メーカー独自情報由来）の値を使う。
            cameraSerialNumber: exif[kCGImagePropertyExifBodySerialNumber] as? String
                ?? exifAux[kCGImagePropertyExifAuxSerialNumber] as? String,
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
        // EXIF 2.31 のタイムゾーン（例: "+09:00"）があれば使い、無ければ端末のタイムゾーンとみなす。
        let timeZone = (exif[kCGImagePropertyExifOffsetTimeOriginal] as? String).flatMap(Self.timeZone(fromOffset:)) ?? .current
        // 連写の順序を保つためにサブ秒も加える。
        let subsecond = (exif[kCGImagePropertyExifSubsecTimeOriginal] as? String).flatMap { Double("0." + $0) } ?? 0
        return exifDateFormatter(timeZone: timeZone).date(from: string)?.addingTimeInterval(subsecond)
    }

    static func exifDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = timeZone
        return formatter
    }

    static func timeZone(fromOffset offset: String) -> TimeZone? {
        let sign: Int = offset.hasPrefix("-") ? -1 : 1
        let parts = offset.trimmingCharacters(in: CharacterSet(charactersIn: "+-")).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return TimeZone(secondsFromGMT: sign * (h * 3600 + m * 60))
    }

    static func coordinate(gps: [CFString: Any]) -> GeoCoordinate? {
        guard let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        // 南緯・西経は負の値にする。
        func sign(_ key: CFString, negativeWhen ref: String) -> Double {
            (gps[key] as? String) == ref ? -1 : 1
        }
        return GeoCoordinate(
            latitude: lat * sign(kCGImagePropertyGPSLatitudeRef, negativeWhen: "S"),
            longitude: lon * sign(kCGImagePropertyGPSLongitudeRef, negativeWhen: "W")
        )
    }
}
#endif
