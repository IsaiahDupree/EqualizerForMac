import Foundation

enum PracticePlanFormatter {
    static func text(for track: PracticeTrack) -> String {
        var lines = [
            "Track Study practice plan",
            "",
            clean(track.title),
            "Duration: \(time(track.duration))",
            "Imported: \(track.importedAt.formatted(date: .abbreviated, time: .omitted))",
            "",
            "Practice markers"
        ]

        let markers = track.markers.sorted { $0.seconds < $1.seconds }
        if markers.isEmpty {
            lines.append("- None saved")
        } else {
            lines += markers.map { "- \(time($0.seconds))  \(clean($0.title))" }
        }

        lines += ["", "A/B repeat loops"]
        let loops = track.loops.sorted { $0.startSeconds < $1.startSeconds }
        if loops.isEmpty {
            lines.append("- None saved")
        } else {
            lines += loops.map {
                "- \(time($0.startSeconds))–\(time($0.endSeconds))  \(clean($0.title))"
            }
        }

        if let analysis = track.analysis {
            lines += ["", "On-device music analysis"]
            if let tempoBPM = analysis.tempoBPM {
                lines.append("Detected beat tempo: \(tempoBPM) BPM")
            }
            if let openingKey = analysis.keySpans.first?.key {
                lines.append("First detected key: \(clean(openingKey))")
            }
            lines.append("Detected sections: \(analysis.sectionSpans.count)")
            lines.append("Analysis is a guide; musical interpretation may be imperfect.")
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

    private static func time(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}
