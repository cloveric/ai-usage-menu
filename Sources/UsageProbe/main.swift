import AIUsageCore
import Darwin
import Foundation

@main
struct UsageProbe {
    static func main() async {
        if CommandLine.arguments.contains("--raw-codex") {
            print(await UsageService().debugCodexRawRateLimits())
            return
        }
        if CommandLine.arguments.contains("--codex-oauth") {
            print(await UsageService().debugCodexOAuthWindows())
            return
        }
        if CommandLine.arguments.contains("--codex-local") {
            print(UsageService().debugCodexLocalWindows())
            return
        }
        if CommandLine.arguments.contains("--claude-oauth") {
            print(await UsageService().debugClaudeOAuthWindows())
            return
        }
        let snapshot = await UsageService().fetchAll(previous: UsageCache.load())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(snapshot)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            FileHandle.standardError.write(Data("编码失败：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
