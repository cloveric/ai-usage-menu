import AppKit
import Foundation

@main
struct GlassBackdrop {
    static func main() {
        guard CommandLine.arguments.count == 2,
              let image = NSImage(contentsOfFile: CommandLine.arguments[1])
        else {
            fputs("usage: glass_backdrop <image>\n", stderr)
            exit(2)
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let primaryScreen = NSScreen.screens.first {
            abs($0.frame.minX) < 1 && abs($0.frame.minY) < 1
        } ?? NSScreen.main
        let visibleFrame = primaryScreen?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let windowSize = NSSize(width: 760, height: 620)
        let window = NSWindow(
            contentRect: NSRect(
                x: visibleFrame.maxX - windowSize.width - 80,
                y: visibleFrame.maxY - windowSize.height - 10,
                width: windowSize.width,
                height: windowSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: windowSize))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        window.contentView = imageView
        window.orderFrontRegardless()

        withExtendedLifetime(window) {
            application.run()
        }
    }
}
