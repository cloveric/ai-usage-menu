import AIUsageCore
import Darwin
import Foundation

@main
struct CoreChecks {
    static func main() {
        var failures: [String] = []
        self.checkKimiParser(failures: &failures)
        self.checkAverage(failures: &failures)
        self.checkQuotaWindowSelection(failures: &failures)
        self.checkFallbackPolicy(failures: &failures)
        self.checkCodexLocalFallback(failures: &failures)
        self.checkLegacyCacheDecoding(failures: &failures)

        if failures.isEmpty {
            print("CoreChecks passed (6/6)")
            return
        }
        for failure in failures {
            FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
        }
        exit(1)
    }

    private static func checkQuotaWindowSelection(failures: inout [String]) {
        let windows = [
            QuotaWindow(usedPercent: 60, windowMinutes: 30 * 24 * 60),
            QuotaWindow(usedPercent: 23, windowMinutes: 7 * 24 * 60),
            QuotaWindow(usedPercent: 11, windowMinutes: 5 * 60),
            QuotaWindow(usedPercent: 4, windowMinutes: 60),
        ]
        if QuotaWindowSelector.weekly(from: windows)?.usedPercent != 23 {
            failures.append("Weekly 选择器误选了月度或短周期窗口")
        }
        if QuotaWindowSelector.fiveHour(from: windows)?.usedPercent != 11 {
            failures.append("5h 选择器没有选中五小时窗口")
        }
        if QuotaWindowSelector.weekly(from: [windows[0]]) != nil {
            failures.append("月度窗口不应被标记为 Weekly")
        }
        if QuotaWindowSelector.fiveHour(from: [windows[3]]) != nil {
            failures.append("一小时窗口不应被标记为 5h")
        }
        let reversed = [windows[1], windows[2]]
        if QuotaWindowSelector.weekly(from: reversed)?.usedPercent != 23
            || QuotaWindowSelector.fiveHour(from: reversed)?.usedPercent != 11
        {
            failures.append("窗口顺序变化时 Weekly/5h 不应依赖 primary/secondary 位置")
        }
        if QuotaWindowSelector.fiveHour(from: [windows[1]]) != nil {
            failures.append("仅返回 Weekly 时不应伪造 5h")
        }
    }

    private static func checkCodexLocalFallback(failures: inout [String]) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("ai-usage-core-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }

        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("rollout-test.jsonl")
            let bothWindows = #"{"timestamp":"2023-11-14T22:11:20.000Z","payload":{"rate_limits":{"plan_type":"pro","primary":{"used_percent":23,"window_minutes":10080,"resets_at":1700500000},"secondary":{"used_percent":11,"window_minutes":300,"resets_at":1700010000}}}}"#
            try Data("\(bothWindows)\n".utf8).write(to: file)

            let now = Date(timeIntervalSince1970: 1_700_000_000)
            guard let both = CodexSessionUsageReader.latestUsage(
                in: [root],
                now: now,
                maximumAge: 60 * 60),
                both.weekly.usedPercent == 23,
                both.fiveHour?.usedPercent == 11
            else {
                failures.append("Codex 本地快照没有按时长恢复 Weekly 与 5h")
                return
            }

            let weeklyOnly = #"{"timestamp":"2023-11-14T22:12:20.000Z","payload":{"rate_limits":{"plan_type":"pro","primary":{"used_percent":8,"window_minutes":10080,"resets_at":1700500000},"secondary":null}}}"#
            try Data("\(bothWindows)\n\(weeklyOnly)\n".utf8).write(to: file)
            guard let latest = CodexSessionUsageReader.latestUsage(
                in: [root],
                now: now,
                maximumAge: 60 * 60),
                latest.weekly.usedPercent == 8,
                latest.fiveHour == nil
            else {
                failures.append("较新的 Weekly-only 快照不应继承旧 5h")
                return
            }

            if CodexSessionUsageReader.latestUsage(
                in: [root],
                now: now.addingTimeInterval(2 * 60 * 60),
                maximumAge: 60 * 60) != nil
            {
                failures.append("超过一小时的 Codex 本地快照不应继续显示")
            }
        } catch {
            failures.append("Codex 本地快照测试失败：\(error.localizedDescription)")
        }
    }

    private static func checkFallbackPolicy(failures: inout [String]) {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = ProviderUsage(
            provider: .kimi,
            main: QuotaWindow(usedPercent: 1, windowMinutes: 7 * 24 * 60),
            fiveHour: QuotaWindow(usedPercent: 0, windowMinutes: 5 * 60),
            connection: .connected,
            source: "test",
            updatedAt: now.addingTimeInterval(-30 * 60))
        if !UsageFallbackPolicy.canUseRecentCache(recent, now: now) {
            failures.append("Kimi 短暂 API 故障时没有优先使用一小时内缓存")
        }

        let old = ProviderUsage(
            provider: .kimi,
            main: recent.main,
            fiveHour: recent.fiveHour,
            connection: .connected,
            source: "test",
            updatedAt: now.addingTimeInterval(-2 * 60 * 60))
        if UsageFallbackPolicy.canUseRecentCache(old, now: now) {
            failures.append("超过一小时的 Kimi 缓存不应阻止 CLI 恢复探测")
        }
    }

    private static func checkKimiParser(failures: inout [String]) {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let output = """
        Kimi Code
        Weekly limit     1% used     Resets in 6d 11h 53m
        5h limit         0% used     Resets in 4h 53m
        """
        do {
            let usage = try KimiTerminalParser.parse(output, now: now)
            guard usage.weekly.usedPercent == 1,
                  usage.weekly.roundedRemainingPercent == 99,
                  usage.fiveHour?.usedPercent == 0,
                  usage.weekly.resetsAt == now.addingTimeInterval(TimeInterval((6 * 24 * 60 + 11 * 60 + 53) * 60))
            else {
                failures.append(
                    "Kimi /usage 百分比或重置时间解析不正确 "
                        + "weekly=\(usage.weekly.usedPercent) "
                        + "fiveHour=\(String(describing: usage.fiveHour?.usedPercent)) "
                        + "reset=\(String(describing: usage.weekly.resetsAt))")
                return
            }
        } catch {
            failures.append("Kimi /usage 样本解析失败：\(error.localizedDescription)")
        }
    }

    private static func checkAverage(failures: inout [String]) {
        let now = Date()
        let snapshot = DashboardSnapshot(
            providers: [
                ProviderUsage(
                    provider: .codex,
                    main: QuotaWindow(usedPercent: 28),
                    fiveHour: QuotaWindow(usedPercent: 4),
                    connection: .connected,
                    source: "test",
                    updatedAt: now),
                ProviderUsage(
                    provider: .claude,
                    main: QuotaWindow(usedPercent: 45),
                    fiveHour: QuotaWindow(usedPercent: 12),
                    fable5: QuotaWindow(usedPercent: 88),
                    connection: .connected,
                    source: "test",
                    updatedAt: now),
                ProviderUsage(
                    provider: .kimi,
                    main: QuotaWindow(usedPercent: 14),
                    fiveHour: QuotaWindow(usedPercent: 1),
                    connection: .connected,
                    source: "test",
                    updatedAt: now),
            ],
            fetchedAt: now)
        if snapshot.averageRemainingPercent != 71 {
            failures.append("菜单栏平均值不应把 5h 或 Fable 5 重复计入")
        }
    }

    private static func checkLegacyCacheDecoding(failures: inout [String]) {
        let legacyJSON = #"{"provider":"codex","main":{"usedPercent":28},"connection":"connected","source":"test"}"#
        do {
            let usage = try JSONDecoder().decode(ProviderUsage.self, from: Data(legacyJSON.utf8))
            if usage.fiveHour != nil || usage.main?.usedPercent != 28 {
                failures.append("旧缓存迁移后 Weekly 或 5h 字段不正确")
            }
        } catch {
            failures.append("新增 5h 字段后无法读取旧缓存：\(error.localizedDescription)")
        }
    }
}
