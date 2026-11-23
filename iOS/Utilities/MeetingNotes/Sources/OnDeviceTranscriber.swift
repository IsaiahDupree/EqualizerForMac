import Foundation
import Speech

enum OnDeviceTranscriber {
    static func authorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static func transcribe(fileURL: URL, locale: Locale = Locale(identifier: "en-US")) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.supportsOnDeviceRecognition else {
            throw MeetingNotesError.onDeviceRecognitionUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            let completion = OneShotSpeechCompletion(continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    completion.finish(.failure(error))
                } else if let result, result.isFinal {
                    completion.finish(.success(result.bestTranscription.formattedString))
                }
            }
        }
    }
}

private final class OneShotSpeechCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
