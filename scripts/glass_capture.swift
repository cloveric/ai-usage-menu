import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

@main
struct GlassCapture {
    static func main() async throws {
        guard CommandLine.arguments.count == 3,
              let processID = pid_t(CommandLine.arguments[1])
        else {
            throw CaptureError.usage
        }

        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false)
        let windows = content.windows.filter { $0.owningApplication?.processID == processID }
        guard !windows.isEmpty else { throw CaptureError.noWindows }

        let captureRect = windows.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard let display = content.displays.first(where: { $0.frame.intersects(captureRect) }) else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, including: windows)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = captureRect.offsetBy(
            dx: -display.frame.minX,
            dy: -display.frame.minY)
        configuration.width = Int(captureRect.width.rounded(.up))
        configuration.height = Int(captureRect.height.rounded(.up))
        configuration.showsCursor = false
        let backgroundColor = CGColor(gray: 0, alpha: 1)
        configuration.backgroundColor = backgroundColor

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration)
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil)
        else {
            throw CaptureError.cannotCreateDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.cannotWriteImage
        }

        print("captured \(windows.count) windows at \(Int(captureRect.width))x\(Int(captureRect.height))")
    }
}

private enum CaptureError: LocalizedError {
    case usage
    case noWindows
    case noDisplay
    case cannotCreateDestination
    case cannotWriteImage

    var errorDescription: String? {
        switch self {
        case .usage: "usage: glass_capture <process-id> <output.png>"
        case .noWindows: "no windows found for process"
        case .noDisplay: "no display intersects the app windows"
        case .cannotCreateDestination: "could not create PNG destination"
        case .cannotWriteImage: "could not write PNG"
        }
    }
}
