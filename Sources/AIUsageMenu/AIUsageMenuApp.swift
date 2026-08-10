import AIUsageCore
import AppKit
import SwiftUI

@main
struct AIUsageMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore.shared

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(store: self.store)
        } label: {
            Text(self.store.menuBarTitle)
                .accessibilityLabel("AI 剩余用量 \(self.store.menuBarTitle)")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewPanel: NSPanel?
    private var glassQABackgroundWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("--preview") else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 326, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.title = "AI 用量"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(
            rootView: UsagePopoverView(store: UsageStore.shared, isPreview: true))
        if ProcessInfo.processInfo.arguments.contains("--glass-qa-background") {
            self.installGlassQABackground(behind: panel)
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.previewPanel = panel
    }

    func applicationWillTerminate(_ notification: Notification) {
        UsageService.terminateActiveProviderProcesses()
    }

    private func installGlassQABackground(behind panel: NSPanel) {
        let backgroundWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        backgroundWindow.isOpaque = true
        backgroundWindow.backgroundColor = .black
        backgroundWindow.level = .normal
        backgroundWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        backgroundWindow.contentViewController = NSHostingController(
            rootView: GlassQABackgroundView(
                isShifted: ProcessInfo.processInfo.arguments.contains("--glass-qa-shifted")))
        let primaryScreen = NSScreen.screens.first {
            abs($0.frame.minX) < 1 && abs($0.frame.minY) < 1
        }
        let screenFrame = (primaryScreen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        backgroundWindow.setFrameOrigin(NSPoint(
            x: screenFrame.midX - backgroundWindow.frame.width / 2,
            y: screenFrame.midY - backgroundWindow.frame.height / 2))
        backgroundWindow.orderFrontRegardless()

        let backgroundFrame = backgroundWindow.frame
        backgroundWindow.addChildWindow(panel, ordered: .above)
        panel.setFrameOrigin(NSPoint(
            x: backgroundFrame.midX - panel.frame.width / 2,
            y: backgroundFrame.midY - panel.frame.height / 2))
        self.glassQABackgroundWindow = backgroundWindow
    }
}

private struct GlassQABackgroundView: View {
    let isShifted: Bool

    private var colors: [Color] {
        if self.isShifted {
            return [.yellow, .purple, .cyan, .red, .green]
        }
        return [.red, .blue, .yellow, .green, .purple]
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(Array(self.colors.enumerated()), id: \.offset) { _, color in
                    color
                }
            }
            VStack(spacing: 22) {
                ForEach(0..<8, id: \.self) { row in
                    Text("GLASS BLUR TEST 0123456789 — ROW \(row + 1)")
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundStyle(row.isMultiple(of: 2) ? Color.white : Color.black)
                }
            }
        }
        .frame(width: 620, height: 500)
    }
}
