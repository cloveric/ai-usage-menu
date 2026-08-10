import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = GlassVisualEffectView()
        view.material = self.material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = self.material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.appearance = NSAppearance(named: .darkAqua)
    }
}

enum GlassStyle {
    static var material: NSVisualEffectView.Material {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--glass-material-menu") { return .menu }
        if arguments.contains("--glass-material-popover") { return .popover }
        if arguments.contains("--glass-material-hud") { return .hudWindow }
        return .sidebar
    }

    static var tintOpacity: Double {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--glass-no-tint") { return 0 }
        if arguments.contains("--glass-heavy-tint") { return 0.28 }
        return 0.12
    }
}

private final class GlassVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }

        let shouldDiagnose = ProcessInfo.processInfo.arguments.contains("--diagnose-glass")
        if shouldDiagnose {
            let contentColor = window.contentView?.layer?.backgroundColor.map(String.init(describing:)) ?? "nil"
            let backgroundColor = String(describing: window.backgroundColor ?? .clear)
            fputs(
                "glass before: class=\(type(of: window)) opaque=\(window.isOpaque) background=\(backgroundColor) contentLayer=\(contentColor)\n",
                stderr)
            fputs("glass hierarchy: \(self.viewHierarchyDescription())\n", stderr)
        }

        // NSVisualEffectView with .behindWindow can only sample the desktop when
        // the hosting window and its root content surface are genuinely clear.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.invalidateShadow()

        if shouldDiagnose {
            let contentColor = window.contentView?.layer?.backgroundColor.map(String.init(describing:)) ?? "nil"
            let backgroundColor = String(describing: window.backgroundColor ?? .clear)
            fputs(
                "glass after: class=\(type(of: window)) opaque=\(window.isOpaque) background=\(backgroundColor) contentLayer=\(contentColor)\n",
                stderr)
        }
    }

    private func viewHierarchyDescription() -> String {
        var items: [String] = []
        var current: NSView? = self
        while let view = current {
            items.append("\(type(of: view))[opaque=\(view.isOpaque),layer=\(view.wantsLayer)]")
            current = view.superview
        }
        return items.joined(separator: " <- ")
    }
}
