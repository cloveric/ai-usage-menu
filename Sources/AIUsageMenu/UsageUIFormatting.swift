import AIUsageCore
import Foundation

@MainActor
enum UsageUIFormatting {
    static func statusText(for snapshot: DashboardSnapshot, now: Date = Date()) -> String {
        if snapshot.fetchedAt == .distantPast { return "等待首次更新" }
        let freshness = self.updatedText(for: snapshot.fetchedAt, now: now)
        if snapshot.hasStaleData { return "\(freshness) · 含缓存" }
        if snapshot.connectedProviderCount == 0 { return "刷新失败" }
        if snapshot.connectedProviderCount < UsageProvider.allCases.count {
            return "\(freshness) · 部分连接"
        }
        return freshness
    }

    static func resetText(for window: QuotaWindow?, now: Date = Date()) -> String {
        guard let window else { return "重置时间未知" }
        guard let reset = window.resetsAt else {
            return window.resetDescription.map { "\($0) 重置" } ?? "重置时间未知"
        }

        let interval = reset.timeIntervalSince(now)
        if interval <= 0 { return "即将刷新" }
        if interval < 90 * 60 {
            return "\(max(1, Int((interval / 60).rounded())))分钟后重置"
        }
        if interval < 12 * 60 * 60 {
            return "\(max(1, Int((interval / 3600).rounded())))小时后重置"
        }

        let calendar = Calendar.current
        let time = self.timeFormatter.string(from: reset)
        if calendar.isDateInTomorrow(reset) {
            return "明天 \(time) 重置"
        }
        if calendar.isDate(reset, equalTo: now, toGranularity: .weekOfYear) {
            return "\(self.weekdayFormatter.string(from: reset)) \(time) 重置"
        }
        return "\(self.dateFormatter.string(from: reset)) \(time) 重置"
    }

    static func updatedText(for date: Date, now: Date = Date()) -> String {
        if date == .distantPast { return "等待首次更新" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 45 { return "刚刚更新" }
        if seconds < 60 * 60 { return "\(Int(seconds / 60))分钟前更新" }
        if seconds < 24 * 60 * 60 { return "\(Int(seconds / 3600))小时前更新" }
        return self.dateTimeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm 更新"
        return formatter
    }()
}
