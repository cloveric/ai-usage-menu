import CodexBarCore
import Foundation

public struct UsageService: Sendable {
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = Self.preparedEnvironment(from: environment)
    }

    public func fetchAll(
        previous: DashboardSnapshot? = nil,
        forceClaudeRefresh: Bool = false) async -> DashboardSnapshot
    {
        let previousCodex = previous?.usage(for: .codex)
        let previousClaude = previous?.usage(for: .claude)
        let previousKimi = previous?.usage(for: .kimi)
        async let codex = self.fetchWithTimeout(provider: .codex, previous: previousCodex) {
            await self.fetchCodexResult(previous: previousCodex)
        }
        async let claude = self.fetchWithTimeout(provider: .claude, previous: previousClaude) {
            await self.fetchClaudeResult(previous: previousClaude, forceRefresh: forceClaudeRefresh)
        }
        async let kimi = self.fetchWithTimeout(provider: .kimi, previous: previousKimi) {
            await self.fetchKimiResult(previous: previousKimi)
        }
        return await DashboardSnapshot(
            providers: [codex, claude, kimi],
            fetchedAt: Date())
    }

    private func fetchWithTimeout(
        provider: UsageProvider,
        previous: ProviderUsage?,
        timeout: Duration = .seconds(35),
        operation: @escaping @Sendable () async -> ProviderUsage) async -> ProviderUsage
    {
        let (results, continuation) = AsyncStream<ProviderUsage>.makeStream(
            bufferingPolicy: .bufferingOldest(1))
        let operationTask = Task {
            continuation.yield(await operation())
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            continuation.yield(Self.failed(
                provider: provider,
                error: ProviderReadError.multiple("\(provider.displayName) 刷新超过 35 秒，已保留缓存"),
                previous: previous))
        }

        return await withTaskCancellationHandler {
            var iterator = results.makeAsyncIterator()
            let first = await iterator.next()
                ?? Self.failed(
                    provider: provider,
                    error: ProviderReadError.multiple("\(provider.displayName) 刷新已取消"),
                    previous: previous)
            operationTask.cancel()
            timeoutTask.cancel()
            continuation.finish()
            return first
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            continuation.finish()
        }
    }

    public static func terminateActiveProviderProcesses() {
        TTYCommandRunner.terminateActiveProcessesForAppShutdown()
    }

    /// Returns the app-server payload used by the Codex quota reader. This is
    /// intentionally diagnostic-only and never written to the usage cache.
    public func debugCodexRawRateLimits() async -> String {
        await UsageFetcher(environment: self.environment).debugRawRateLimits()
    }

    /// Probes the authenticated ChatGPT usage endpoint without exposing OAuth
    /// credentials. The output contains quota metadata only.
    public func debugCodexOAuthWindows() async -> String {
        do {
            let credentials = try CodexOAuthCredentialsStore.loadOAuthTokens(env: self.environment)
            let response = try await CodexOAuthUsageFetcher.fetchUsage(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId,
                env: self.environment)
            func dictionary(_ window: CodexUsageResponse.WindowSnapshot?) -> [String: Any]? {
                guard let window else { return nil }
                return [
                    "usedPercent": window.usedPercent,
                    "windowMinutes": window.limitWindowSeconds / 60,
                    "resetsAt": window.resetAt,
                ]
            }
            var payload: [String: Any] = ["planType": response.planType?.rawValue ?? "unknown"]
            payload["primary"] = dictionary(response.rateLimit?.primaryWindow) ?? NSNull()
            payload["secondary"] = dictionary(response.rateLimit?.secondaryWindow) ?? NSNull()
            payload["additionalLimits"] = response.additionalRateLimits?.map { entry -> [String: Any] in
                [
                    "limitName": entry.limitName ?? NSNull(),
                    "meteredFeature": entry.meteredFeature ?? NSNull(),
                    "primary": dictionary(entry.rateLimit?.primaryWindow) ?? NSNull(),
                    "secondary": dictionary(entry.rateLimit?.secondaryWindow) ?? NSNull(),
                ]
            } ?? []
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "Codex OAuth probe failed: \(error.localizedDescription)"
        }
    }

    /// Reports the latest recent local Codex rate-limit event without decoding
    /// or emitting conversation content, and without exposing credentials.
    public func debugCodexLocalWindows() -> String {
        guard let snapshot = CodexSessionUsageReader.latestUsage(environment: self.environment) else {
            return #"{"available":false}"#
        }
        func dictionary(_ window: QuotaWindow?) -> [String: Any]? {
            guard let window else { return nil }
            return [
                "usedPercent": window.usedPercent,
                "windowMinutes": window.windowMinutes ?? NSNull(),
                "resetsAt": window.resetsAt?.timeIntervalSince1970 ?? NSNull(),
            ]
        }
        let payload: [String: Any] = [
            "available": true,
            "updatedAt": snapshot.updatedAt.timeIntervalSince1970,
            "planType": snapshot.planType ?? NSNull(),
            "weekly": dictionary(snapshot.weekly) ?? NSNull(),
            "fiveHour": dictionary(snapshot.fiveHour) ?? NSNull(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return #"{"available":false}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Checks the lightweight Claude OAuth path and returns quota metadata only.
    public func debugClaudeOAuthWindows() async -> String {
        do {
            let oauth = try await self.fetchClaudeOAuth(environment: self.environment)
            let snapshot = oauth.snapshot
            var payload: [String: Any] = [
                "primaryMinutes": snapshot.primary.windowMinutes.map { $0 as Any } ?? NSNull(),
                "secondaryMinutes": snapshot.secondary?.windowMinutes.map { $0 as Any } ?? NSNull(),
                "extraTitles": snapshot.extraRateWindows.map(\.title),
                "hasTerminalText": snapshot.rawText != nil,
                "source": oauth.source,
            ]
            payload["primaryUsedPercent"] = snapshot.primary.usedPercent
            payload["secondaryUsedPercent"] = snapshot.secondary?.usedPercent ?? NSNull()
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "Claude OAuth probe failed: \(error.localizedDescription)"
        }
    }

    /// Checks Claude through the credential-owning CLI and emits quota
    /// metadata only. This is used to validate the no-Keychain-UI recovery
    /// path; terminal text and credentials are never included in the output.
    public func debugClaudeCLIWindows() async -> String {
        do {
            var preparedEnvironment = self.environment
            preparedEnvironment["CLAUDE_CODE_SAFE_MODE"] = "1"
            let environment = preparedEnvironment
            let snapshot = try await ProviderProcessGate.shared.run {
                try await ClaudeUsageFetcher(
                    browserDetection: BrowserDetection(),
                    environment: environment,
                    runtime: .cli,
                    dataSource: .cli,
                    keepCLISessionsAlive: false)
                    .loadLatestUsage()
            }
            let payload: [String: Any] = [
                "primaryMinutes": snapshot.primary.windowMinutes ?? NSNull(),
                "primaryUsedPercent": snapshot.primary.usedPercent,
                "secondaryMinutes": snapshot.secondary?.windowMinutes ?? NSNull(),
                "secondaryUsedPercent": snapshot.secondary?.usedPercent ?? NSNull(),
                "extraTitles": snapshot.extraRateWindows.map(\.title),
                "hasTerminalText": snapshot.rawText != nil,
                "source": "Claude CLI /usage（安全模式）",
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "Claude CLI probe failed: \(error.localizedDescription)"
        }
    }

    /// Checks Kimi's structured usage endpoint without emitting credentials.
    /// Only quota percentages, reset timestamps and the source label are
    /// included in the diagnostic output.
    public func debugKimiAPIWindows() async -> String {
        do {
            let usage = try await self.fetchKimiViaAPI()
            func dictionary(_ window: QuotaWindow?) -> [String: Any]? {
                guard let window else { return nil }
                return [
                    "usedPercent": window.usedPercent,
                    "remainingPercent": window.remainingPercent,
                    "windowMinutes": window.windowMinutes ?? NSNull(),
                    "resetsAt": window.resetsAt?.timeIntervalSince1970 ?? NSNull(),
                ]
            }
            let payload: [String: Any] = [
                "source": usage.source,
                "weekly": dictionary(usage.main) ?? NSNull(),
                "fiveHour": dictionary(usage.fiveHour) ?? NSNull(),
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "Kimi API probe failed: \(error.localizedDescription)"
        }
    }

    private func fetchCodexResult(previous: ProviderUsage?) async -> ProviderUsage {
        var oauthError: Error?
        do {
            let credentials = try CodexOAuthCredentialsStore.loadOAuthTokens(env: self.environment)
            let response = try await CodexOAuthUsageFetcher.fetchUsage(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId,
                env: self.environment)
            let windows = [
                response.rateLimit?.primaryWindow,
                response.rateLimit?.secondaryWindow,
            ].compactMap { $0 }.map(Self.quota(from:))
            guard let weekly = QuotaWindowSelector.weekly(from: windows) else {
                throw ProviderReadError.noQuota("Codex OAuth 没有返回周额度")
            }
            let fiveHour = QuotaWindowSelector.fiveHour(from: windows)
            return ProviderUsage(
                provider: .codex,
                main: weekly,
                fiveHour: fiveHour,
                connection: .connected,
                source: "Codex OAuth",
                updatedAt: Date(),
                errorMessage: Self.codexFiveHourNote(fiveHour))
        } catch {
            if Self.isCancellation(error) {
                return Self.failed(provider: .codex, error: error, previous: previous)
            }
            oauthError = error
            if let previous, UsageFallbackPolicy.canUseRecentCache(previous) {
                let cachedError = ProviderReadError.multiple(
                    "Codex OAuth 暂时失败：\(error.localizedDescription)；已保留最近缓存，未启动 app-server")
                return previous.keepingCachedValue(after: cachedError)
            }
        }

        if let local = CodexSessionUsageReader.latestUsage(environment: self.environment) {
            let liveError = oauthError?.localizedDescription ?? "实时读取不可用"
            return ProviderUsage(
                provider: .codex,
                main: local.weekly,
                fiveHour: local.fiveHour,
                connection: .stale,
                source: "Codex 本地会话快照",
                updatedAt: local.updatedAt,
                errorMessage: "Codex 实时读取失败：\(liveError)；显示一小时内的本地快照")
        }

        do {
            let environment = self.environment
            let snapshot = try await ProviderProcessGate.shared.run {
                do {
                    return try await UsageFetcher(environment: environment).loadLatestUsage()
                } catch {
                    if Self.isCancellation(error) { throw error }
                    try await Task.sleep(for: .milliseconds(250))
                    return try await UsageFetcher(environment: environment).loadLatestUsage()
                }
            }
            guard let main = Self.preferredWeeklyWindow(primary: snapshot.primary, secondary: snapshot.secondary) else {
                throw ProviderReadError.noQuota("Codex app-server 没有返回周额度")
            }
            let fiveHour = Self.preferredFiveHourWindow(
                primary: snapshot.primary,
                secondary: snapshot.secondary).map(Self.quota(from:))
            return ProviderUsage(
                provider: .codex,
                main: Self.quota(from: main),
                fiveHour: fiveHour,
                connection: .connected,
                source: "Codex app-server",
                updatedAt: snapshot.updatedAt,
                errorMessage: Self.codexFiveHourNote(fiveHour))
        } catch {
            let combined = oauthError.map {
                ProviderReadError.multiple("Codex OAuth：\($0.localizedDescription)；app-server：\(error.localizedDescription)")
            } ?? error
            return Self.failed(provider: .codex, error: combined, previous: previous)
        }
    }

    private func fetchClaudeResult(previous: ProviderUsage?, forceRefresh: Bool) async -> ProviderUsage {
        if !forceRefresh,
           let previous,
           ClaudeRefreshPolicy.canReuseAutomaticSnapshot(previous)
        {
            return previous
        }

        var preparedClaudeEnvironment = self.environment
        // Keeps built-in /usage and authentication while disabling project
        // hooks, plugins, LSPs and MCP startup for this read-only probe.
        preparedClaudeEnvironment["CLAUDE_CODE_SAFE_MODE"] = "1"
        let claudeEnvironment = preparedClaudeEnvironment

        var oauthError: Error?
        if Self.hasClaudeEnvironmentOAuthToken(claudeEnvironment) {
            do {
                let oauth = try await self.fetchClaudeOAuth(environment: claudeEnvironment)
                return try Self.claudeUsage(from: oauth.snapshot, source: oauth.source)
            } catch {
                if Self.isCancellation(error) {
                    return Self.failed(provider: .claude, error: error, previous: previous)
                }
                oauthError = error
            }
        }

        do {
            let snapshot = try await self.fetchClaudeViaCLI(environment: claudeEnvironment)
            let usage = try Self.claudeUsage(
                from: snapshot,
                source: "Claude CLI /usage（30 分钟自动刷新）")
            return Self.restoringRecentFableIfNeeded(usage, previous: previous)
        } catch {
            let combined = oauthError.map {
                ProviderReadError.multiple(
                    "Claude 环境 OAuth：\($0.localizedDescription)；CLI：\(error.localizedDescription)")
            } ?? error
            return Self.failed(provider: .claude, error: combined, previous: previous)
        }
    }

    private func fetchClaudeOAuth(environment: [String: String]) async throws
        -> (snapshot: ClaudeUsageSnapshot, source: String)
    {
        guard Self.hasClaudeEnvironmentOAuthToken(environment) else {
            throw ProviderReadError.noQuota(
                "未配置 CODEXBAR_CLAUDE_OAUTH_TOKEN；不会读取 Claude Code 钥匙串")
        }
        let snapshot = try await ClaudeUsageFetcher(
            browserDetection: BrowserDetection(),
            environment: environment,
            runtime: .cli,
            dataSource: .oauth,
            oauthSafeCredentialSourcesOnly: true,
            allowBackgroundDelegatedRefresh: false)
            .loadLatestUsage()
        return (snapshot, "Claude OAuth（环境变量）")
    }

    private func fetchClaudeViaCLI(environment: [String: String]) async throws -> ClaudeUsageSnapshot {
        try await ProviderProcessGate.shared.run {
            try await ClaudeUsageFetcher(
                browserDetection: BrowserDetection(),
                environment: environment,
                runtime: .cli,
                dataSource: .cli,
                keepCLISessionsAlive: false)
                .loadLatestUsage()
        }
    }

    private static func hasClaudeEnvironmentOAuthToken(_ environment: [String: String]) -> Bool {
        !(environment[ClaudeOAuthCredentialsStore.environmentTokenKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true)
    }

    private static func claudeUsage(
        from snapshot: ClaudeUsageSnapshot,
        source: String) throws -> ProviderUsage
    {
        let fable = Self.fableWindow(in: snapshot)
        guard let mainWindow = Self.preferredWeeklyWindow(
            primary: snapshot.primary,
            secondary: snapshot.secondary)
        else {
            throw ProviderReadError.noQuota("Claude 没有返回周额度")
        }
        return ProviderUsage(
            provider: .claude,
            main: Self.quota(from: mainWindow),
            fiveHour: Self.preferredFiveHourWindow(
                primary: snapshot.primary,
                secondary: snapshot.secondary).map(Self.quota(from:)),
            fable5: fable.map(Self.quota(from:)),
            connection: .connected,
            source: source,
            updatedAt: snapshot.updatedAt,
            errorMessage: fable == nil ? "Fable 5 暂未出现在用量响应中" : nil)
    }

    private static func restoringRecentFableIfNeeded(
        _ usage: ProviderUsage,
        previous: ProviderUsage?) -> ProviderUsage
    {
        guard usage.fable5 == nil,
              let cachedFable = ClaudeFableFallbackPolicy.reusableWindow(from: previous)
        else {
            return usage
        }
        return ProviderUsage(
            provider: usage.provider,
            main: usage.main,
            fiveHour: usage.fiveHour,
            fable5: cachedFable,
            connection: usage.connection,
            source: usage.source,
            updatedAt: usage.updatedAt,
            errorMessage: "Fable 5 本次未完成渲染，暂用当前周期的最近值")
    }

    private func fetchKimiResult(previous: ProviderUsage?) async -> ProviderUsage {
        let firstAPIError: Error
        do {
            return try await self.fetchKimiViaAPI()
        } catch {
            if Self.isCancellation(error) {
                return Self.failed(provider: .kimi, error: error, previous: previous)
            }
            firstAPIError = error
        }

        // Keep a recent value for transient API failures, but never let a
        // near-expiry/invalid credential hide behind the cache: the official
        // Kimi CLI owns refresh-token rotation and must be allowed to refresh it.
        if let previous,
           UsageFallbackPolicy.canUseRecentCache(previous),
           !Self.isKimiCredentialError(firstAPIError)
        {
            let cachedError = ProviderReadError.multiple(
                "Kimi API 暂时失败：\(firstAPIError.localizedDescription)；已保留最近缓存")
            return previous.keepingCachedValue(after: cachedError)
        }

        var terminalUsage: KimiTerminalUsage?
        var terminalError: Error?
        do {
            terminalUsage = try await self.fetchKimiViaTerminal()
        } catch {
            if Self.isCancellation(error) {
                return Self.failed(provider: .kimi, error: error, previous: previous)
            }
            terminalError = error
        }

        // `/usage` can rotate Kimi's short-lived access token even when its
        // terminal redraw is incomplete. Re-read the credential file and retry
        // the structured endpoint before trusting parsed terminal text.
        do {
            return try await self.fetchKimiViaAPI()
        } catch {
            if Self.isCancellation(error) {
                return Self.failed(provider: .kimi, error: error, previous: previous)
            }
            if let terminal = terminalUsage {
                return ProviderUsage(
                    provider: .kimi,
                    main: terminal.weekly,
                    fiveHour: terminal.fiveHour,
                    connection: .connected,
                    source: "Kimi CLI /usage",
                    updatedAt: Date(),
                    errorMessage: "API 重试失败，已使用 CLI 实时值：\(error.localizedDescription)")
            }

            let cliMessage = terminalError?.localizedDescription ?? "没有返回可解析的用量"
            let combinedError = ProviderReadError.multiple(
                "Kimi API：\(firstAPIError.localizedDescription)；CLI：\(cliMessage)；API 重试：\(error.localizedDescription)")
            return Self.failed(provider: .kimi, error: combinedError, previous: previous)
        }
    }

    private func fetchKimiViaAPI() async throws -> ProviderUsage {
        let token: String
        if let codeToken = KimiSettingsReader.kimiCodeAccessToken(environment: self.environment) {
            token = codeToken
        } else if let configuredAPIKey = KimiSettingsReader.apiKey(environment: self.environment) {
            token = configuredAPIKey
        } else if KimiSettingsReader.hasKimiCodeCredential(environment: self.environment) {
            throw KimiAPIError.expiredCodeCredential
        } else {
            throw KimiAPIError.missingToken
        }

        let baseURL = try KimiSettingsReader.codeAPIBaseURL(environment: self.environment)
        let snapshot = try await self.fetchKimiAPISnapshot(apiKey: token, baseURL: baseURL)
        guard let main = Self.preferredWeeklyWindow(
            primary: snapshot.primary,
            secondary: snapshot.secondary)
        else {
            throw ProviderReadError.noQuota("Kimi API 没有返回周额度")
        }
        return ProviderUsage(
            provider: .kimi,
            main: Self.quota(from: main),
            fiveHour: Self.preferredFiveHourWindow(
                primary: snapshot.primary,
                secondary: snapshot.secondary).map(Self.quota(from:)),
            connection: .connected,
            source: "Kimi Code API",
            updatedAt: snapshot.updatedAt)
    }

    private static func isKimiCredentialError(_ error: Error) -> Bool {
        guard let kimiError = error as? KimiAPIError else { return false }
        return switch kimiError {
        case .missingToken, .invalidToken, .missingAPIKey, .invalidAPIKey,
             .expiredCodeCredential, .invalidCodeCredential:
            true
        case .invalidRequest, .networkError, .apiError, .parseFailed:
            false
        }
    }

    private func fetchKimiViaTerminal() async throws -> KimiTerminalUsage {
        let environment = self.environment
        let binary = Self.kimiBinary(environment: environment)
        let text = try await ProviderProcessGate.shared.run {
            try await Task.detached(priority: .utility) {
                var options = TTYCommandRunner.Options(
                    rows: 50,
                    cols: 150,
                    timeout: 24,
                    idleTimeout: nil,
                    baseEnvironment: environment,
                    initialDelay: 2.0,
                    stopOnSubstrings: ["5h limit"],
                    settleAfterStop: 2.0,
                    returnOnEmptyProcessExit: true)
                options.sendEnterEvery = nil
                let result = try TTYCommandRunner().run(binary: binary, send: "/usage\r", options: options)
                return result.text
            }.value
        }
        return try KimiTerminalParser.parse(text)
    }

    private func fetchKimiAPISnapshot(apiKey: String, baseURL: URL) async throws -> UsageSnapshot {
        do {
            return try await KimiUsageFetcher.fetchCodeAPIUsage(apiKey: apiKey, baseURL: baseURL)
                .toUsageSnapshot()
        } catch {
            if Self.isCancellation(error) { throw error }
            try await Task.sleep(for: .milliseconds(300))
            return try await KimiUsageFetcher.fetchCodeAPIUsage(apiKey: apiKey, baseURL: baseURL)
                .toUsageSnapshot()
        }
    }

    private static func preferredWeeklyWindow(primary: RateWindow?, secondary: RateWindow?) -> RateWindow? {
        let candidates = [primary, secondary].compactMap { $0 }.filter { !$0.isSyntheticPlaceholder }
        guard let selected = QuotaWindowSelector.weekly(from: candidates.map(Self.quota(from:))) else { return nil }
        return candidates.first { Self.quota(from: $0) == selected }
    }

    private static func preferredFiveHourWindow(primary: RateWindow?, secondary: RateWindow?) -> RateWindow? {
        let candidates = [primary, secondary].compactMap { $0 }.filter { !$0.isSyntheticPlaceholder }
        guard let selected = QuotaWindowSelector.fiveHour(from: candidates.map(Self.quota(from:))) else { return nil }
        return candidates.first { Self.quota(from: $0) == selected }
    }

    private static func fableWindow(in snapshot: ClaudeUsageSnapshot) -> RateWindow? {
        snapshot.extraRateWindows.first { window in
            let haystack = "\(window.id) \(window.title)".lowercased()
            return haystack.contains("fable")
        }?.window
    }

    private static func quota(from window: RateWindow) -> QuotaWindow {
        QuotaWindow(
            usedPercent: window.usedPercent,
            windowMinutes: window.windowMinutes,
            resetsAt: window.resetsAt ?? Self.parseLooseResetDate(window.resetDescription),
            resetDescription: window.resetDescription)
    }

    private static func quota(from window: CodexUsageResponse.WindowSnapshot) -> QuotaWindow {
        let reset = Date(timeIntervalSince1970: TimeInterval(window.resetAt))
        return QuotaWindow(
            usedPercent: Double(window.usedPercent),
            windowMinutes: window.limitWindowSeconds / 60,
            resetsAt: reset,
            resetDescription: nil)
    }

    private static func codexFiveHourNote(_ fiveHour: QuotaWindow?) -> String? {
        fiveHour == nil ? "Codex 当前未返回 5h；Weekly 数据正常" : nil
    }

    private static func parseLooseResetDate(_ description: String?, now: Date = Date()) -> Date? {
        guard let description,
              let regex = try? NSRegularExpression(
                  pattern: #"(?i)(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*([0-9]{1,2}).*?([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)"#)
        else {
            return nil
        }
        let range = NSRange(description.startIndex..<description.endIndex, in: description)
        guard let match = regex.firstMatch(in: description, options: [], range: range),
              match.numberOfRanges >= 6,
              let monthText = Self.capture(1, from: match, in: description),
              let month = Self.monthNumber(monthText),
              let dayText = Self.capture(2, from: match, in: description),
              let day = Int(dayText),
              let hourText = Self.capture(3, from: match, in: description),
              var hour = Int(hourText),
              let meridiem = Self.capture(5, from: match, in: description)?.lowercased()
        else {
            return nil
        }
        let minute = Self.capture(4, from: match, in: description).flatMap(Int.init) ?? 0
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }

        let timeZone = Self.captureTimeZone(from: description) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let year = calendar.component(.year, from: now)
        guard var date = calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute))
        else {
            return nil
        }
        if date < now.addingTimeInterval(-24 * 60 * 60),
           let nextYear = calendar.date(byAdding: .year, value: 1, to: date)
        {
            date = nextYear
        }
        return date
    }

    private static func capture(_ index: Int, from match: NSTextCheckingResult, in text: String) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    private static func captureTimeZone(from description: String) -> TimeZone? {
        guard let open = description.lastIndex(of: "("),
              let close = description[open...].firstIndex(of: ")"),
              open < close
        else {
            return nil
        }
        let identifier = String(description[description.index(after: open)..<close])
        return TimeZone(identifier: identifier)
    }

    private static func monthNumber(_ abbreviation: String) -> Int? {
        ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            .firstIndex(of: abbreviation.lowercased())
            .map { $0 + 1 }
    }

    private static func failed(provider: UsageProvider, error: Error, previous: ProviderUsage?) -> ProviderUsage {
        if let previous, UsageFallbackPolicy.canUseRecentCache(previous) {
            return previous.keepingCachedValue(after: error)
        }
        return .disconnected(provider, message: error.localizedDescription)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private static func kimiBinary(environment: [String: String]) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            environment["KIMI_BINARY"],
            "\(home)/.kimi-code/bin/kimi",
            "/opt/homebrew/bin/kimi",
            "/usr/local/bin/kimi",
        ].compactMap { $0 }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "kimi"
    }

    private static func preparedEnvironment(from base: [String: String]) -> [String: String] {
        var environment = base
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let additions = [
            "\(home)/.kimi-code/bin",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let existing = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        environment["PATH"] = Array(NSOrderedSet(array: additions + existing))
            .compactMap { $0 as? String }
            .joined(separator: ":")
        environment["TERM"] = "xterm-256color"
        environment["NO_COLOR"] = "1"
        return environment
    }
}

private enum ProviderReadError: LocalizedError, Sendable {
    case noQuota(String)
    case multiple(String)

    var errorDescription: String? {
        switch self {
        case let .noQuota(message), let .multiple(message): message
        }
    }
}

private actor ProviderProcessGate {
    static let shared = ProviderProcessGate()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await self.acquire()
        do {
            let value = try await operation()
            self.release()
            return value
        } catch {
            self.release()
            throw error
        }
    }

    private func acquire() async {
        guard self.isRunning else {
            self.isRunning = true
            return
        }
        await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    private func release() {
        guard !self.waiters.isEmpty else {
            self.isRunning = false
            return
        }
        self.waiters.removeFirst().resume()
    }
}
