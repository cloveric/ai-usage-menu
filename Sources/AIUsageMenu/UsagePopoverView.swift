import AIUsageCore
import AppKit
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var store: UsageStore
    var isPreview = false

    var body: some View {
        ZStack {
            VisualEffectBackground(material: GlassStyle.material)
                .ignoresSafeArea()
            Color(red: 0.045, green: 0.070, blue: 0.115)
                .opacity(GlassStyle.tintOpacity)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                self.header
                GlassDivider()
                ProviderRow(
                    usage: self.store.snapshot.usage(for: .codex),
                    accent: ProviderPalette.codex,
                    assetName: "codex-mark",
                    tileColor: ProviderPalette.iconTile)
                GlassDivider()
                ProviderRow(
                    usage: self.store.snapshot.usage(for: .claude),
                    accent: ProviderPalette.claude,
                    assetName: "claude-mark",
                    tileColor: ProviderPalette.iconTile,
                    showsFable: true)
                GlassDivider()
                ProviderRow(
                    usage: self.store.snapshot.usage(for: .kimi),
                    accent: ProviderPalette.kimi,
                    assetName: "kimi-mark",
                    tileColor: ProviderPalette.iconTile)

                if self.store.showsDetails {
                    GlassDivider()
                    DetailsPanel(snapshot: self.store.snapshot)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                GlassDivider()
                self.footer
            }
            .padding(.horizontal, 16)
        }
        .frame(width: 326)
        .fixedSize(horizontal: true, vertical: true)
        .preferredColorScheme(.dark)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.18), value: self.store.showsDetails)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI 用量面板")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 用量")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(UsageUIFormatting.statusText(for: self.store.snapshot))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
            Spacer(minLength: 8)
            RefreshButton(isRefreshing: self.store.isRefreshing) {
                Task { await self.store.refresh() }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                self.store.showsDetails.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(self.store.showsDetails ? "收起详情" : "查看详情")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(self.store.showsDetails ? 90 : 0))
                }
                .foregroundStyle(.white.opacity(0.68))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("展开数据来源和错误信息")

            Spacer()
            ConnectionStatus(snapshot: self.store.snapshot)
        }
        .padding(.vertical, 10)
    }
}

private struct ProviderRow: View {
    let usage: ProviderUsage
    let accent: Color
    let assetName: String
    let tileColor: Color
    var showsFable = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            BrandIcon(assetName: self.assetName, accent: self.accent, tileColor: self.tileColor)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 0) {
                Text(self.usage.provider.displayName)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(alignment: .top, spacing: 10) {
                    QuotaColumn(title: "Weekly", window: self.usage.main, accent: self.accent)
                    QuotaColumn(
                        title: "5h",
                        window: self.usage.fiveHour,
                        accent: self.accent,
                        unavailableText: self.fiveHourUnavailableText)
                }
                .padding(.top, 2)

                if self.showsFable {
                    FableQuotaView(window: self.usage.fable5)
                        .padding(.top, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let weekly = self.usage.main?.roundedRemainingPercent.description ?? "未知"
        let fiveHour = self.usage.fiveHour?.roundedRemainingPercent.description ?? "未知"
        let fable = self.usage.fable5.map { "，Fable 5 剩余 \($0.roundedRemainingPercent)%" } ?? ""
        return "\(self.usage.provider.displayName)，Weekly 剩余 \(weekly)%，5h 剩余 \(fiveHour)%\(fable)"
    }

    private var fiveHourUnavailableText: String {
        if self.usage.provider == .codex, self.usage.main != nil, self.usage.fiveHour == nil {
            return "服务端暂未返回"
        }
        return "暂无数据"
    }
}

private struct QuotaColumn: View {
    let title: String
    let window: QuotaWindow?
    let accent: Color
    var unavailableText = "暂无数据"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(self.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 3)
                if let window {
                    Text("\(window.roundedRemainingPercent)%")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(self.accent)
                } else {
                    Text("--")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.34))
                }
            }
            UsageProgressBar(value: self.window?.remainingPercent, color: self.accent, height: 4)
            Text(self.window.map { UsageUIFormatting.resetText(for: $0) } ?? self.unavailableText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FableQuotaView: View {
    let window: QuotaWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Fable 5")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                if let window {
                    Text("\(window.roundedRemainingPercent)%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(ProviderPalette.fable)
                    Text("剩余")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                } else {
                    Text("暂不可用")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 5)
                Text(UsageUIFormatting.resetText(for: self.window))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }
            UsageProgressBar(value: self.window?.remainingPercent, color: ProviderPalette.fable, height: 4)
        }
    }
}

private struct UsageProgressBar: View {
    let value: Double?
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                Capsule()
                    .fill(self.color)
                    .frame(width: proxy.size.width * CGFloat((self.value ?? 0) / 100))
            }
        }
        .frame(height: self.height)
        .accessibilityHidden(true)
    }
}

private struct BrandIcon: View {
    let assetName: String
    let accent: Color
    let tileColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(self.tileColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.09), lineWidth: 0.7)
                }
            if let image = BrandAsset.image(named: self.assetName) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(self.accent)
                    .padding(8)
            }
        }
        .frame(width: 40, height: 40)
        .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

@MainActor
private enum BrandAsset {
    private static var cache: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let cached = self.cache[name] { return cached }
        let image: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let bundledImage = NSImage(contentsOf: url)
        {
            image = bundledImage
        } else {
            let developmentURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("\(name).png", isDirectory: false)
            image = NSImage(contentsOf: developmentURL)
        }
        if let image { self.cache[name] = image }
        return image
    }
}

private struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: self.action) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(self.isHovered ? 0.15 : 0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 0.7)
                    }
                if self.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(self.isRefreshing)
        .onHover { self.isHovered = $0 }
        .help("立即刷新")
        .accessibilityLabel("刷新全部用量")
    }
}

private struct ConnectionStatus: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(self.color)
                .frame(width: 8, height: 8)
                .shadow(color: self.color.opacity(0.30), radius: 3)
            Text(self.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
        }
        .accessibilityLabel(self.label)
    }

    private var color: Color {
        if self.snapshot.connectedProviderCount == UsageProvider.allCases.count { return Color.green.opacity(0.92) }
        if self.snapshot.connectedProviderCount > 0 || self.snapshot.hasStaleData { return Color.orange.opacity(0.95) }
        return Color.red.opacity(0.90)
    }

    private var label: String {
        if self.snapshot.connectedProviderCount == UsageProvider.allCases.count { return "全部已连接" }
        if self.snapshot.hasStaleData { return "部分数据已缓存" }
        return "\(self.snapshot.connectedProviderCount)/\(UsageProvider.allCases.count) 已连接"
    }
}

private struct DetailsPanel: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(self.snapshot.providers) { usage in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(usage.provider.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(usage.source)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        if let error = usage.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(usage.connection == .connected
                                    ? Color.orange.opacity(0.78)
                                    : Color.red.opacity(0.82))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Text(self.connectionLabel(usage.connection))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.connectionColor(usage.connection))
                }
            }

            HStack {
                Text("每 15 分钟自动刷新")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                Button("退出 AI 用量") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 14)
    }

    private func connectionLabel(_ connection: ProviderConnection) -> String {
        switch connection {
        case .connected: "实时"
        case .stale: "缓存"
        case .disconnected: "未连接"
        }
    }

    private func connectionColor(_ connection: ProviderConnection) -> Color {
        switch connection {
        case .connected: Color.green.opacity(0.82)
        case .stale: Color.orange.opacity(0.88)
        case .disconnected: Color.red.opacity(0.84)
        }
    }
}

private struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 0.5)
    }
}

private enum ProviderPalette {
    static let codex = Color(red: 0.33, green: 0.61, blue: 0.93)
    static let claude = Color(red: 0.91, green: 0.60, blue: 0.38)
    static let fable = Color(red: 0.90, green: 0.42, blue: 0.36)
    static let kimi = Color(red: 0.57, green: 0.50, blue: 0.88)
    static let iconTile = Color.black.opacity(0.28)
}
