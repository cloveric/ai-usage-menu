import CodexBarCore
import Foundation

public struct KimiTerminalUsage: Equatable, Sendable {
    public let weekly: QuotaWindow
    public let fiveHour: QuotaWindow?

    public init(weekly: QuotaWindow, fiveHour: QuotaWindow?) {
        self.weekly = weekly
        self.fiveHour = fiveHour
    }
}

public enum KimiTerminalParserError: LocalizedError, Sendable {
    case weeklyLimitMissing

    public var errorDescription: String? {
        switch self {
        case .weeklyLimitMissing:
            "Kimi /usage 没有返回周额度，请先在终端运行 kimi 并完成登录。"
        }
    }
}

public enum KimiTerminalParser {
    public static func parse(_ rawText: String, now: Date = Date()) throws -> KimiTerminalUsage {
        let text = self.normalized(rawText)
        guard let weekly = self.window(after: "Weekly limit", in: text, minutes: 7 * 24 * 60, now: now) else {
            throw KimiTerminalParserError.weeklyLimitMissing
        }
        let fiveHour = self.window(after: "5h limit", in: text, minutes: 5 * 60, now: now)
        return KimiTerminalUsage(weekly: weekly, fiveHour: fiveHour)
    }

    private static func normalized(_ rawText: String) -> String {
        let withoutANSI = TextParsing.stripANSICodes(rawText)
        let withoutOSC = withoutANSI.replacingOccurrences(
            of: #"\u001B\][^\u0007]*(?:\u0007|\u001B\\)"#,
            with: " ",
            options: .regularExpression)
        let scalars = withoutOSC.unicodeScalars.map { scalar -> String in
            if CharacterSet.controlCharacters.contains(scalar), scalar != "\n", scalar != "\r", scalar != "\t" {
                return " "
            }
            return String(scalar)
        }.joined()
        return scalars
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func window(
        after label: String,
        in text: String,
        minutes: Int,
        now: Date) -> QuotaWindow?
    {
        // Terminal UIs redraw the same row several times. The final redraw can
        // contain only the label, so try every occurrence from newest to oldest
        // instead of trusting the final one unconditionally.
        for labelRange in self.ranges(of: label, in: text).reversed() {
            if let window = self.window(
                after: labelRange,
                in: text,
                minutes: minutes,
                now: now)
            {
                return window
            }
        }
        return nil
    }

    private static func window(
        after labelRange: Range<String.Index>,
        in text: String,
        minutes: Int,
        now: Date) -> QuotaWindow?
    {
        let rawTail = String(text[labelRange.upperBound...].prefix(700))
        let boundaryOffsets = ["Weekly limit", "5h limit"].compactMap { boundary in
            rawTail.range(of: boundary, options: .caseInsensitive)?.lowerBound
        }
        let tail = boundaryOffsets.min().map { String(rawTail[..<$0]) } ?? rawTail
        guard let used = self.firstDouble(
            pattern: #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%\s*used"#,
            in: tail)
        else {
            return nil
        }

        let durationText = self.firstCapture(
            pattern: #"resets?\s+in\s+((?:[0-9]+\s*[dhm]\s*)+)"#,
            in: tail)
        let resetsAt = durationText.flatMap { self.date(after: $0, from: now) }
        return QuotaWindow(
            usedPercent: used,
            windowMinutes: minutes,
            resetsAt: resetsAt,
            resetDescription: durationText.map { "in \($0)" })
    }

    private static func ranges(of needle: String, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                  of: needle,
                  options: .caseInsensitive,
                  range: searchStart..<text.endIndex)
        {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    private static func firstDouble(pattern: String, in text: String) -> Double? {
        self.firstCapture(pattern: pattern, in: text).flatMap(Double.init)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func date(after duration: String, from now: Date) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]+)\s*([dhm])"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(duration.startIndex..<duration.endIndex, in: duration)
        var seconds: TimeInterval = 0
        for match in regex.matches(in: duration, range: range) {
            guard match.numberOfRanges > 2,
                  let valueRange = Range(match.range(at: 1), in: duration),
                  let unitRange = Range(match.range(at: 2), in: duration),
                  let value = Double(duration[valueRange])
            else {
                continue
            }
            switch duration[unitRange].lowercased() {
            case "d": seconds += value * 24 * 60 * 60
            case "h": seconds += value * 60 * 60
            case "m": seconds += value * 60
            default: break
            }
        }
        return seconds > 0 ? now.addingTimeInterval(seconds) : nil
    }
}
