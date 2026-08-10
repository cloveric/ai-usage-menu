import Foundation

public enum UsageProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case kimi

    public var id: String { self.rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .kimi: "Kimi"
        }
    }
}

public enum ProviderConnection: String, Codable, Sendable {
    case connected
    case stale
    case disconnected
}

public struct QuotaWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let resetDescription: String?

    public init(
        usedPercent: Double,
        windowMinutes: Int? = nil,
        resetsAt: Date? = nil,
        resetDescription: String? = nil)
    {
        self.usedPercent = min(100, max(0, usedPercent))
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }

    public var remainingPercent: Double {
        min(100, max(0, 100 - self.usedPercent))
    }

    public var roundedRemainingPercent: Int {
        Int(self.remainingPercent.rounded())
    }
}

/// Selects only windows that can be labelled confidently in the UI. This
/// avoids presenting a monthly/daily cap as "Weekly", or an arbitrary short
/// rate limit as "5h" when a provider changes its response shape.
public enum QuotaWindowSelector {
    public static let weeklyMinutes = 7 * 24 * 60
    public static let fiveHourMinutes = 5 * 60

    public static func weekly(from windows: [QuotaWindow]) -> QuotaWindow? {
        self.closest(
            to: self.weeklyMinutes,
            tolerance: 12 * 60,
            in: windows)
    }

    public static func fiveHour(from windows: [QuotaWindow]) -> QuotaWindow? {
        self.closest(
            to: self.fiveHourMinutes,
            tolerance: 30,
            in: windows)
    }

    private static func closest(
        to targetMinutes: Int,
        tolerance: Int,
        in windows: [QuotaWindow]) -> QuotaWindow?
    {
        windows
            .filter { window in
                guard let minutes = window.windowMinutes, minutes > 0 else { return false }
                return abs(minutes - targetMinutes) <= tolerance
            }
            .min { lhs, rhs in
                abs((lhs.windowMinutes ?? 0) - targetMinutes)
                    < abs((rhs.windowMinutes ?? 0) - targetMinutes)
            }
    }
}

public enum UsageFallbackPolicy {
    public static func canUseRecentCache(
        _ usage: ProviderUsage,
        now: Date = Date(),
        maximumAge: TimeInterval = 60 * 60) -> Bool
    {
        guard maximumAge >= 0, usage.main != nil, let updatedAt = usage.updatedAt else { return false }
        return max(0, now.timeIntervalSince(updatedAt)) <= maximumAge
    }
}

public struct ProviderUsage: Codable, Equatable, Identifiable, Sendable {
    public let provider: UsageProvider
    /// The long-running quota lane used for the menu bar aggregate.
    public let main: QuotaWindow?
    /// The provider's short session/rate-limit lane, normally five hours.
    public let fiveHour: QuotaWindow?
    public let fable5: QuotaWindow?
    public let connection: ProviderConnection
    public let source: String
    public let updatedAt: Date?
    public let errorMessage: String?

    public var id: UsageProvider { self.provider }

    public init(
        provider: UsageProvider,
        main: QuotaWindow?,
        fiveHour: QuotaWindow? = nil,
        fable5: QuotaWindow? = nil,
        connection: ProviderConnection,
        source: String,
        updatedAt: Date?,
        errorMessage: String? = nil)
    {
        self.provider = provider
        self.main = main
        self.fiveHour = fiveHour
        self.fable5 = fable5
        self.connection = connection
        self.source = source
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
    }

    public static func disconnected(_ provider: UsageProvider, message: String) -> Self {
        Self(
            provider: provider,
            main: nil,
            connection: .disconnected,
            source: "未连接",
            updatedAt: nil,
            errorMessage: message)
    }

    public func keepingCachedValue(after error: Error) -> Self {
        Self(
            provider: self.provider,
            main: self.main,
            fiveHour: self.fiveHour,
            fable5: self.fable5,
            connection: .stale,
            source: self.source,
            updatedAt: self.updatedAt,
            errorMessage: error.localizedDescription)
    }
}

public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public let providers: [ProviderUsage]
    public let fetchedAt: Date

    public init(providers: [ProviderUsage], fetchedAt: Date) {
        self.providers = UsageProvider.allCases.compactMap { provider in
            providers.first(where: { $0.provider == provider })
        }
        self.fetchedAt = fetchedAt
    }

    public func usage(for provider: UsageProvider) -> ProviderUsage {
        self.providers.first(where: { $0.provider == provider })
            ?? .disconnected(provider, message: "尚未读取用量")
    }

    public var averageRemainingPercent: Int? {
        let values = self.providers.compactMap { $0.main?.remainingPercent }
        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }

    public var connectedProviderCount: Int {
        self.providers.filter { $0.connection == .connected }.count
    }

    public var hasStaleData: Bool {
        self.providers.contains { $0.connection == .stale }
    }

    public static let empty = DashboardSnapshot(
        providers: UsageProvider.allCases.map {
            .disconnected($0, message: "正在等待首次刷新")
        },
        fetchedAt: .distantPast)

    public static func designFixture(now: Date = Date(), calendar: Calendar = .current) -> Self {
        let codexFiveHourReset = now.addingTimeInterval(4 * 60 * 60)
        let claudeFiveHourReset = now.addingTimeInterval(3 * 60 * 60 + 30 * 60)
        let kimiFiveHourReset = now.addingTimeInterval(4 * 60 * 60 + 30 * 60)
        let nextFriday = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 9, minute: 0, weekday: 6),
            matchingPolicy: .nextTime) ?? now.addingTimeInterval(4 * 24 * 60 * 60)
        let fableReset = nextFriday.addingTimeInterval(-60)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))

        return Self(
            providers: [
                ProviderUsage(
                    provider: .codex,
                    main: QuotaWindow(
                        usedPercent: 28,
                        windowMinutes: 7 * 24 * 60,
                        resetsAt: nextFriday),
                    fiveHour: QuotaWindow(
                        usedPercent: 9,
                        windowMinutes: 5 * 60,
                        resetsAt: codexFiveHourReset),
                    connection: .connected,
                    source: "Codex app-server",
                    updatedAt: now),
                ProviderUsage(
                    provider: .claude,
                    main: QuotaWindow(
                        usedPercent: 45,
                        windowMinutes: 7 * 24 * 60,
                        resetsAt: nextFriday),
                    fiveHour: QuotaWindow(
                        usedPercent: 21,
                        windowMinutes: 5 * 60,
                        resetsAt: claudeFiveHourReset),
                    fable5: QuotaWindow(
                        usedPercent: 88,
                        windowMinutes: 7 * 24 * 60,
                        resetsAt: fableReset),
                    connection: .connected,
                    source: "Claude OAuth / CLI",
                    updatedAt: now),
                ProviderUsage(
                    provider: .kimi,
                    main: QuotaWindow(
                        usedPercent: 14,
                        windowMinutes: 7 * 24 * 60,
                        resetsAt: tomorrow),
                    fiveHour: QuotaWindow(
                        usedPercent: 0,
                        windowMinutes: 5 * 60,
                        resetsAt: kimiFiveHourReset),
                    connection: .connected,
                    source: "Kimi Code API",
                    updatedAt: now),
            ],
            fetchedAt: now)
    }
}
