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

