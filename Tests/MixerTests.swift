import Foundation
import Testing
@testable import SonanceEQ

@Suite struct MixerChannelTests {
    @Test func unityGainByDefault() {
        #expect(MixerChannel(bundleID: "a", name: "A").gain == 1)
    }

    @Test func mutedGainIsZero() {
        var c = MixerChannel(bundleID: "a", name: "A"); c.muted = true
        #expect(c.gain == 0)
    }

    @Test func volumeClampedToMax() {
        var c = MixerChannel(bundleID: "a", name: "A"); c.volume = 5
        #expect(c.gain == MixerChannel.maxVolume)
    }

    @Test func negativeVolumeClampsToZero() {
        var c = MixerChannel(bundleID: "a", name: "A"); c.volume = -2
        #expect(c.gain == 0)
    }

    @Test func passthroughDetection() {
        #expect(MixerChannel(bundleID: "a", name: "A").isPassthrough)
        var v = MixerChannel(bundleID: "a", name: "A"); v.volume = 0.5
        #expect(!v.isPassthrough)
        var m = MixerChannel(bundleID: "a", name: "A"); m.muted = true
        #expect(!m.isPassthrough)
        var o = MixerChannel(bundleID: "a", name: "A"); o.outputDeviceUID = "BuiltInSpeaker"
        #expect(!o.isPassthrough)
    }
}

@MainActor
@Suite struct MixerStateTests {
    private func fresh() -> (MixerState, String) {
        let suite = "test.mixer.\(UUID().uuidString)"
        return (MixerState(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    @Test func defaultChannelIsPassthroughAndNotActive() {
        let (m, s) = fresh()
        #expect(m.channel("x", name: "X").isPassthrough)
        #expect(m.activeChannels.isEmpty)
        UserDefaults().removePersistentDomain(forName: s)
    }

    @Test func setVolumeCreatesActiveChannel() {
        let (m, s) = fresh()
        m.setVolume(0.5, for: "x", name: "X")
        #expect(m.channels["x"]?.volume == 0.5)
        #expect(m.activeChannels.count == 1)
        UserDefaults().removePersistentDomain(forName: s)
    }

    @Test func volumeIsClampedInState() {
        let (m, s) = fresh()
        m.setVolume(9, for: "x", name: "X")
        #expect(m.channels["x"]?.volume == MixerChannel.maxVolume)
        UserDefaults().removePersistentDomain(forName: s)
    }

    @Test func backToUnityRemovesChannel() {
        let (m, s) = fresh()
        m.setVolume(0.4, for: "x", name: "X")
        m.setVolume(1.0, for: "x", name: "X")   // passthrough again
        #expect(m.channels["x"] == nil)
        #expect(m.activeChannels.isEmpty)
        UserDefaults().removePersistentDomain(forName: s)
    }

    @Test func muteAndOutputCreateChannels() {
        let (m, s) = fresh()
        m.setMuted(true, for: "x", name: "X")
        m.setOutput("BuiltInSpeaker", for: "y", name: "Y")
        #expect(m.channels["x"]?.muted == true)
        #expect(m.channels["y"]?.outputDeviceUID == "BuiltInSpeaker")
        #expect(m.activeChannels.count == 2)
        UserDefaults().removePersistentDomain(forName: s)
    }

    @Test func persistsAcrossInstances() {
        let suite = "test.mixer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        MixerState(defaults: defaults).setVolume(0.3, for: "x", name: "X")
        #expect(MixerState(defaults: defaults).channels["x"]?.volume == 0.3)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func resetForgetsChannel() {
        let (m, s) = fresh()
        m.setMuted(true, for: "x", name: "X")
        m.reset("x")
        #expect(m.channels["x"] == nil)
        UserDefaults().removePersistentDomain(forName: s)
    }
}

@Suite struct AudioDeviceTests {
    // Lenient: a CI runner may have no audio hardware. Assert invariants that hold regardless.
    @Test func enumeratedDevicesHaveIdentity() {
        for d in AudioDevices.outputDevices() {
            #expect(!d.uid.isEmpty)
            #expect(!d.name.isEmpty)
        }
    }

    @Test func devicesAreSortedByName() {
        let devices = AudioDevices.outputDevices()
        #expect(zip(devices, devices.dropFirst()).allSatisfy {
            $0.name.localizedCaseInsensitiveCompare($1.name) != .orderedDescending
        })
    }

    @Test func bogusUIDResolvesToNil() {
        #expect(AudioDevices.deviceID(forUID: "no.such.device.uid.zzz") == nil)
    }
}
