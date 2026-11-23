import Foundation

enum MeetingNotesExport {
    static func text(for session: MeetingSession, summaryIsCurrent: Bool) -> String {
        var lines = [
            "Clear Record meeting notes",
            "",
            clean(session.title),
            "Recorded: \(session.createdAt.formatted(date: .long, time: .shortened))",
            "Duration: \(duration(session.duration))"
        ]

        if let summary = session.aiSummary, !summary.isEmpty {
            lines += ["", summaryIsCurrent ? "Summary" : "Summary (transcript changed after this draft)", summary]
            lines.append("Review the summary for errors before relying on it.")
        }

        if !session.transcript.isEmpty {
            lines += ["", "Transcript", session.transcript]
        }

        if let bookmarks = session.bookmarks, !bookmarks.isEmpty {
            lines += ["", "Bookmarked moments"]
            lines += bookmarks.map { "\(duration($0.time)) — \(clean($0.title))" }
        }

        lines += ["", "Audio is not included in this text export."]
        return lines.joined(separator: "\n")
    }

    private static func clean(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "Unknown" }
        let total = Int(min(seconds.rounded(.down), 4_000_000_000_000_000_000))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}
