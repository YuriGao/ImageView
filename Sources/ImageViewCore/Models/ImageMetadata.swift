import Foundation

public struct ImageMetadata: Equatable, Sendable {
    public let url: URL
    public let format: SupportedImageFormat
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let fileSize: Int64?
    public let modifiedAt: Date?
    public let capturedAt: Date?
    public let cameraMake: String?
    public let cameraModel: String?
    public let colorSpace: String?
    public let colorProfile: String?
    public let bitDepth: Int?
    public let orientation: Int?
    public let exposureTime: Double?
    public let aperture: Double?
    public let isoSpeed: Int?
    public let focalLength: Double?

    public init(
        url: URL,
        format: SupportedImageFormat,
        pixelWidth: Int,
        pixelHeight: Int,
        fileSize: Int64?,
        modifiedAt: Date?,
        capturedAt: Date? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        colorSpace: String? = nil,
        colorProfile: String? = nil,
        bitDepth: Int? = nil,
        orientation: Int? = nil,
        exposureTime: Double? = nil,
        aperture: Double? = nil,
        isoSpeed: Int? = nil,
        focalLength: Double? = nil
    ) {
        self.url = url
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.capturedAt = capturedAt
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.colorSpace = colorSpace
        self.colorProfile = colorProfile
        self.bitDepth = bitDepth
        self.orientation = orientation
        self.exposureTime = exposureTime
        self.aperture = aperture
        self.isoSpeed = isoSpeed
        self.focalLength = focalLength
    }
}
