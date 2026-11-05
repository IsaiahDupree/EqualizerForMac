import Foundation

public enum SonanceApp: String, CaseIterable, Codable, Sendable, Identifiable {
    case eq = "sonance_eq", mixer = "sonance_mixer", recorder = "sonance_recorder"
    case voice = "sonance_voice", diagram = "diagram_studio", scribe = "sonance_scribe"
    case align = "sonance_align", preflight = "sonance_preflight"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .eq: return "Sonance EQ"
        case .mixer: return "Sonance Mixer"
        case .recorder: return "Sonance Recorder"
        case .voice: return "Sonance Voice"
        case .diagram: return "Sonance Diagram Studio"
        case .scribe: return "Sonance Scribe"
        case .align: return "Sonance Align"
        case .preflight: return "Sonance Preflight"
        }
    }
    public var features: [SonanceFeature] {
        let common: [SonanceFeature] = [.appOpen]
        switch self {
        case .eq: return common + [.equalizer, .headphonePresets, .presetSearch, .builtInPresets,
                                   .presetImport, .presetExport, .perAppMixing, .recording, .audioPermission]
        case .mixer: return common + [.mixing, .volume, .mute, .outputRouting, .channelReset, .audioPermission]
        case .recorder: return common + [.recording, .recordingSource, .recordingFormat, .recordingReveal, .audioPermission]
        case .voice: return common + [.enhancement, .monitoring, .voiceSettings, .recording, .recordingReveal, .audioPermission]
        case .diagram: return common + [.diagramOpen, .diagramCreate, .diagramImport, .diagramRemix,
                                        .diagramRestore, .diagramExport]
        case .scribe: return common + [.recording, .transcription, .transcriptionRetry, .meetingSearch,
                                       .meetingFilter, .meetingSort, .transcriptOpen, .fileReveal, .audioDeletion, .audioPermission]
        case .align: return common + [.onboarding, .roomSetup, .roomScan, .measurement,
                                      .recommendation, .verification, .reportExport, .arGuide]
        case .preflight: return common + [.analysis, .deliveryProfile, .reportExport]
        }
    }
}

// Only these identifiers can leave the app. Never use user text, app/device names,
// document titles, search terms, model measurements, file paths, or source content.
public enum SonanceFeature: String, CaseIterable, Codable, Sendable, Identifiable {
    case appOpen = "app_open", equalizer, headphonePresets = "headphone_presets"
    case presetSearch = "preset_search", builtInPresets = "built_in_presets"
    case presetImport = "preset_import", presetExport = "preset_export"
    case perAppMixing = "per_app_mixing", recording, audioPermission = "audio_permission"
    case mixing, volume, mute, outputRouting = "output_routing", channelReset = "channel_reset"
    case recordingSource = "recording_source", recordingFormat = "recording_format", recordingReveal = "recording_reveal"
    case enhancement, monitoring, voiceSettings = "voice_settings"
    case diagramOpen = "diagram_open", diagramCreate = "diagram_create", diagramImport = "diagram_import"
    case diagramRemix = "diagram_remix", diagramRestore = "diagram_restore", diagramExport = "diagram_export"
    case transcription, transcriptionRetry = "transcription_retry", meetingSearch = "meeting_search"
    case meetingFilter = "meeting_filter", meetingSort = "meeting_sort", transcriptOpen = "transcript_open"
    case fileReveal = "file_reveal", audioDeletion = "audio_deletion"
    case onboarding, roomSetup = "room_setup", roomScan = "room_scan", measurement, recommendation, verification
    case reportExport = "report_export", arGuide = "ar_guide", analysis, deliveryProfile = "delivery_profile"
    public var id: String { rawValue }
    public var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

public enum FeatureOutcome: String, CaseIterable, Codable, Sendable {
    case started, succeeded, failed, cancelled, blocked
}
public enum FeatureReason: String, CaseIterable, Codable, Sendable {
    case none, permissionDenied = "permission_denied", unavailable, deviceUnavailable = "device_unavailable"
    case operationFailed = "operation_failed", noResults = "no_results", proRequired = "pro_required"
    case userCancelled = "user_cancelled", emptyResult = "empty_result"
    public func supports(_ outcome: FeatureOutcome) -> Bool {
        switch outcome {
        case .started, .succeeded: return self == .none
        case .cancelled: return self == .userCancelled
        case .failed: return [.operationFailed, .deviceUnavailable, .emptyResult].contains(self)
        case .blocked: return [.permissionDenied, .unavailable, .deviceUnavailable, .proRequired, .noResults].contains(self)
        }
    }
}
public enum FeatureFeedback: String, CaseIterable, Codable, Sendable, Identifiable {
    case worksWell = "works_well", savesTime = "saves_time", betterSound = "better_sound"
    case workOrStudy = "work_or_study", hardToFind = "hard_to_find", permissionProblem = "permission_problem"
    case compatibilityProblem = "compatibility_problem", missingOption = "missing_option", unexpectedResult = "unexpected_result"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .worksWell: return "It works well for me"
        case .savesTime: return "It saves me time"
        case .betterSound: return "It improves my sound"
        case .workOrStudy: return "I use it for work or study"
        case .hardToFind: return "I had trouble finding it"
        case .permissionProblem: return "I am stuck on permissions"
        case .compatibilityProblem: return "It does not work with my setup"
        case .missingOption: return "An option I need is missing"
        case .unexpectedResult: return "The result was unexpected"
        }
    }
}
