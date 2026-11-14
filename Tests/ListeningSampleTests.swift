import AVFoundation
import Testing
@testable import SonanceEQ

@Suite struct ListeningSampleTests {
    @Test func previewChangesTheSampleAndMaintainsTheSameLevel() throws {
        let preview = ListeningSample.render()
        #expect(preview.original.count == ListeningSample.sampleRate * 2)
        #expect(preview.tuned.count == preview.original.count)
        #expect(preview.original != preview.tuned)
        let originalLevel = ListeningSample.rms(preview.original)
        let tunedLevel = ListeningSample.rms(preview.tuned)
        #expect(originalLevel > 0.02)
        #expect(abs(originalLevel - tunedLevel) < 0.00001)
        for take in [preview.original, preview.tuned] {
            #expect(take.allSatisfy { $0.isFinite && abs($0) <= ListeningSample.peakLimit + 0.00001 })
            let player = try AVAudioPlayer(data: ListeningSample.wave(take))
            #expect(abs(player.duration - 2) < 0.01)
            #expect(player.numberOfChannels == 1)
        }
    }
}
