import Foundation

public struct CodexLocalUsageSnapshot: Equatable, Sendable {
    public let weekly: QuotaWindow
    public let fiveHour: QuotaWindow?
    public let updatedAt: Date
    public let planType: String?

    public init(
        weekly: QuotaWindow,
        fiveHour: QuotaWindow?,
        updatedAt: Date,
        planType: String?)
    {
        self.weekly = weekly
        self.fiveHour = fiveHour
        self.updatedAt = updatedAt
        self.planType = planType
    }
}

/// Reads only the numeric `rate_limits` object from recent Codex JSONL files.
/// This is a stale-data fallback for a failed live request, never a replacement
/// for an authoritative live response that intentionally omits a window.
public enum CodexSessionUsageReader {
    public static func latestUsage(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        maximumAge: TimeInterval = 60 * 60) -> CodexLocalUsageSnapshot?
    {
        let home: URL
        if let configured = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty
        {
            home = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
        return self.latestUsage(
            in: [
                home.appendingPathComponent("sessions", isDirectory: true),
                home.appendingPathComponent("archived_sessions", isDirectory: true),
            ],
            now: now,
            maximumAge: maximumAge)
    }

    public static func latestUsage(
        in roots: [URL],
        now: Date,
        maximumAge: TimeInterval = 60 * 60,
        maximumFiles: Int = 8,
        maximumBytesPerFile: Int = 2 * 1024 * 1024) -> CodexLocalUsageSnapshot?
    {
        guard maximumAge >= 0, maximumFiles > 0, maximumBytesPerFile > 0 else { return nil }
        let oldestAllowed = now.addingTimeInterval(-maximumAge)
        let files = self.recentJSONLFiles(in: roots, modifiedAfter: oldestAllowed)
            .prefix(maximumFiles)

        for file in files {
            guard let snapshot = self.latestSnapshot(
                in: file.url,
                fallbackDate: file.modifiedAt,
                now: now,
                oldestAllowed: oldestAllowed,
                maximumBytes: maximumBytesPerFile)
            else {
                continue
            }
            return snapshot
        }
        return nil
    }

    private static func recentJSONLFiles(
        in roots: [URL],
        modifiedAfter cutoff: Date) -> [(url: URL, modifiedAt: Date)]
    {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        var files: [(url: URL, modifiedAt: Date)] = []

        for root in roots {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else {
                continue
            }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt >= cutoff
                else {
                    continue
                }
                files.append((url, modifiedAt))
            }
        }

        return files.sorted { lhs, rhs in lhs.modifiedAt > rhs.modifiedAt }
    }

    private static func latestSnapshot(
        in url: URL,
        fallbackDate: Date,
        now: Date,
        oldestAllowed: Date,
        maximumBytes: Int) -> CodexLocalUsageSnapshot?
    {
        guard let data = self.tailData(from: url, maximumBytes: maximumBytes) else { return nil }
        let decoder = JSONDecoder()

        for rawLine in data.split(separator: 0x0A).reversed() {
            guard rawLine.count < 512 * 1024 else { continue }
            let line = Data(rawLine)
            guard line.range(of: Data(#""rate_limits""#.utf8)) != nil,
                  let event = try? decoder.decode(SessionEvent.self, from: line),
                  let limits = event.payload?.rateLimits ?? event.rateLimits
            else {
                continue
            }

            let updatedAt = self.parseDate(event.timestamp) ?? fallbackDate
            guard updatedAt >= oldestAllowed, updatedAt <= now.addingTimeInterval(5 * 60) else { continue }

            let windows = [limits.primary, limits.secondary]
                .compactMap { $0 }
                .map { window in
                    QuotaWindow(
                        usedPercent: window.usedPercent,
                        windowMinutes: window.windowMinutes,
                        resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) })
                }
                .filter { window in
                    window.resetsAt.map { $0 > now } ?? true
                }
            guard let weekly = QuotaWindowSelector.weekly(from: windows) else { continue }
            return CodexLocalUsageSnapshot(
                weekly: weekly,
                fiveHour: QuotaWindowSelector.fiveHour(from: windows),
                updatedAt: updatedAt,
                planType: limits.planType)
        }
        return nil
    }

    private static func tailData(from url: URL, maximumBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            let end = try handle.seekToEnd()
            let count = min(UInt64(maximumBytes), end)
            try handle.seek(toOffset: end - count)
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct SessionEvent: Decodable {
    let timestamp: String?
    let payload: SessionPayload?
    let rateLimits: SessionRateLimits?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case payload
        case rateLimits = "rate_limits"
    }
}

private struct SessionPayload: Decodable {
    let rateLimits: SessionRateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

private struct SessionRateLimits: Decodable {
    let primary: SessionRateWindow?
    let secondary: SessionRateWindow?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct SessionRateWindow: Decodable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}
