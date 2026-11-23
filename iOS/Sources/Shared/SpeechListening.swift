import Foundation

/// Starting points for spoken recordings, not voice isolation or noise removal.
enum SpeechListening: String, CaseIterable, Identifiable {
    case podcast, audiobook, interview, dialogue

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var description: String {
        switch self {
        case .podcast: return "Reduce low rumble and bring speech forward."
        case .audiobook: return "A gentler lift for longer listening."
        case .interview: return "Reduce boominess and emphasize speech."
        case .dialogue: return "Bring dialogue forward and soften the highs."
        }
    }

    var settings: MobileEQSettings {
        let gains: [Float]
        switch self {
        case .podcast: gains = [-5, -4, -3, -2, 0, 1, 2, 1, 0, -1]
        case .audiobook: gains = [-3, -3, -2, -1, 0, 1, 1, 0, -1, -2]
        case .interview: gains = [-5, -4, -3, -2, -1, 1, 2, 2, 0, -1]
        case .dialogue: gains = [-4, -3, -2, -1, 0, 1, 2, 1, -1, -3]
        }
        return MobileEQSettings(bands: Presets.graphic(gains: gains), preamp: -3, bypassed: false)
    }
}

enum SoundStarterPreset: String, CaseIterable, Identifiable {
    case workout, focus, lateNight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workout: "Workout"
        case .focus: "Focus"
        case .lateNight: "Late Night"
        }
    }

    var description: String {
        switch self {
        case .workout: "Add modest low-end and upper-mid presence."
        case .focus: "Keep the tone even, with a little more midrange presence."
        case .lateNight: "A softer, less bright tone; this does not compress or limit volume."
        }
    }

    private var gains: [Float] {
        switch self {
        case .workout: [2, 3, 2, 1, 0, 1, 2, 2, 1, 0]
        case .focus: [-2, -1, 0, 1, 2, 2, 1, 0, -1, -2]
        case .lateNight: [0, -1, -1, 0, 1, 1, 0, -1, -2, -3]
        }
    }

    func makeSettings(sampleRate: Double = 48_000) -> MobileEQSettings {
        MobileEQSettings.startingPoint(bands: Presets.graphic(gains: gains), sampleRate: sampleRate)
    }
}

