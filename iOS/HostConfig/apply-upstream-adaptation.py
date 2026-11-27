#!/usr/bin/env python3
"""Apply the small Sonance identity bridge to the pinned EffectDeck source tree."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / "Vendor" / "EffectDeck"
host_config = Path(__file__).resolve().parent
(root / "Sources/EffeTuneLive/Audio/ETRouteChangeHistory.swift").write_text(
    (host_config / "ETRouteChangeHistory.swift").read_text(encoding="utf-8"), encoding="utf-8")
(root / "Tests/Unit/ETRouteChangeHistoryTests.swift").write_text(
    (host_config / "ETRouteChangeHistoryTests.swift").read_text(encoding="utf-8"), encoding="utf-8")
changes = {
    root / "Sources/Shared/ETNames.h": {
        '#define ET_NAME_STEM "EffectDeck"': '#define ET_NAME_STEM "Sonance EQ"',
        '#define ET_ROUTE_NAME "EffectDeck"': '#define ET_ROUTE_NAME "Sonance EQ"',
        '#define ET_DRIVER_NAME "EffectDeck"': '#define ET_DRIVER_NAME "Sonance EQ"',
        '#define ET_MANUFACTURER "nemut.ai"': '#define ET_MANUFACTURER "IsDp"',
    },
    root / "Sources/EffeTuneLive/Audio/AudioSessionRules.swift": {
        'static let nameStem = "EffectDeck"': 'static let nameStem = "Sonance EQ"',
    },
    root / "Sources/EffeTuneLive/Audio/NowPlayingMode.swift": {
        'static let title = "EffectDeck"': 'static let title = "Sonance EQ"',
    },
    root / "Sources/EffeTuneLive/Views/StatusReadings.swift": {
        '// **ConnectBanner と同じ字にする。**同じ「まだ音が来ていない」間に出る。':
        '// 受信側では、未選択と非対応プレイヤーを区別できない。ここでは\n'
        '        // 「No audio」を明示し、iOS が iPhone/CarPlay へ戻した場合の回復策も出す。',
        'return "Pick EffectDeck as the output in Control Center."':
        'return "No audio is reaching Sonance EQ. If the player says it does not support EffectDeck Audio or Sonance EQ Audio, it cannot send audio to that route. Choose CarPlay directly for car audio, or use a compatible player or local file for EQ. If audio switches back without that message, tap Help."',
        'return "Pick Sonance EQ as the output in Control Center."':
        'return "No audio is reaching Sonance EQ. If the player says it does not support EffectDeck Audio or Sonance EQ Audio, it cannot send audio to that route. Choose CarPlay directly for car audio, or use a compatible player or local file for EQ. If audio switches back without that message, tap Help."',
    },
    root / "Sources/EffeTuneLive/Views/PipelineView.swift": {
        'Image(systemName: restartNeeded ? "exclamationmark.triangle.fill" : "airplayaudio")':
        'Image(systemName: (restartNeeded || routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst) ? "exclamationmark.triangle.fill" : "airplayaudio")',
        '.foregroundStyle(restartNeeded ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tint))':
        '.foregroundStyle(restartNeeded ? AnyShapeStyle(Color.red) : (routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst) ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))',
        '.foregroundStyle(restartNeeded ? Color.red : Color.primary)':
        '.foregroundStyle(restartNeeded ? Color.red : (routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst) ? Color.orange : Color.primary)',
    },
    root / "Sources/Extension/EffeTuneLiveExtension.swift": {
        'let kProtocolID = "media-device-protocol.ai.nemut.effetune"':
        'let kProtocolID = "media-device-protocol.com.isaiahdupree.SonanceEQ.iOSPrototype"',
        'import Foundation\nimport MediaDevice':
        'import Foundation\nimport ExtensionFoundation\nimport MediaDevice',
        '            self?.reportStatus()':
        '            Task { @MainActor [weak self] in self?.reportStatus() }',
    },
    root / "Sources/EffeTuneLive/DSP/ETShareInbox.swift": {
        'static let group = "group.ai.nemut.effetune"':
        'static let group = "group.com.isaiahdupree.SonanceEQ"',
    },
    root / "Sources/ShareExtension/ShareViewController.swift": {
        '.navigationTitle("EffectDeck")': '.navigationTitle("Sonance EQ")',
    },
    root / "Sources/EffeTuneLive/Views/ConnectionTipsView.swift": {
        '    let ja: Copy\n    var id: Int { issue }':
        '    let ja: Copy\n    var referenceURL: URL? = nil\n    var id: Int { issue }',
        '    var url: URL { URL(string: "https://github.com/satomasahiro2005/EffectDeck/issues/\\(issue)")! }':
        '    var url: URL { referenceURL ?? URL(string: "https://github.com/satomasahiro2005/EffectDeck/issues/\\(issue)")! }',
        '"Restart EffectDeck."': '"Restart Sonance EQ."',
        '"EffectDeckを再起動する"': '"Sonance EQを再起動する"',
        'cannot connect to EffectDeck': 'cannot connect to Sonance EQ',
        'connection to EffectDeck.': 'connection to Sonance EQ.',
        'EffectDeckに接続できない': 'Sonance EQに接続できない',
        'EffectDeckへの接続が拒否': 'Sonance EQへの接続が拒否',
        'Spotify, then connect to EffectDeck again.':
            'Spotify, then connect to Sonance EQ again.',
        'Spotifyを再起動してから、もう一度EffectDeckに接続してください。':
            'Spotifyを再起動してから、もう一度Sonance EQに接続してください。',
        'may disconnect EffectDeck': 'may disconnect Sonance EQ',
        'YouTube, then connect to EffectDeck again.':
            'YouTube, then connect to Sonance EQ again.',
        'to EffectDeck.': 'to Sonance EQ.',
        'EffectDeckとの接続が切れる': 'Sonance EQとの接続が切れる',
        'EffectDeckとの接続を解除': 'Sonance EQとの接続を解除',
        'もう一度EffectDeckに接続してください。':
            'もう一度Sonance EQに接続してください。',
        'static let linkLabel = (en: "Details (GitHub)", ja: "詳細（GitHub・英語）")':
            'static let linkLabel = (en: "Reference", ja: "参考情報")',
        '                        why: "YouTubeの再生状態によっては、iOSがSonance EQとの接続を解除することがあります。")),\n    ]\n}':
            '                        why: "YouTubeの再生状態によっては、iOSがSonance EQとの接続を解除することがあります。")),\n'
            '        ETTip(issue: 5,\n'
            '              en: .init(title: "A player says it does not support EffectDeck Audio or Sonance EQ Audio",\n'
            '                        act: "Choose CarPlay directly to restore car audio, or play a local file in Sonance EQ. For streaming EQ, use a player that supports the Sonance EQ route.",\n'
            '                        why: "A player must support Apple\'s AVSystemRouting API to send audio to the selected route. Sonance EQ cannot make another app accept an unsupported route, so iOS may return playback to iPhone or CarPlay."),\n'
            '              ja: .init(title: "プレイヤーに「EffectDeck Audio」または「Sonance EQ Audio」はサポートされていませんと表示される",\n'
            '                        act: "車の音声を戻すにはCarPlayを直接選ぶか、Sonance EQでローカルファイルを再生してください。ストリーミング音声は、Sonance EQルートに対応したプレイヤーをお使いください。",\n'
            '                        why: "iOSがこのルートへ音声を送るには、プレイヤー側がAppleのAVSystemRouting APIに対応している必要があります。非対応のプレイヤーからSonance EQが音声を取り出すことはできないため、iOSがiPhoneやCarPlayへ戻す場合があります。"),\n'
            '              referenceURL: URL(string: "https://developer.apple.com/documentation/MediaDevice/creating-a-media-device-extension")),\n    ]\n}',
    },
}
for path, replacements in changes.items():
    source = path.read_text()
    for old, new in replacements.items():
        if old in source:
            source = source.replace(old, new)
    pipeline_route_warning = (
        path.name == "PipelineView.swift"
        and "let routeWarning =" in source
        and "carAudioEQBounce" in source
        and 'Image(systemName: (restartNeeded || routeWarning) ? "exclamationmark.triangle.fill" : "airplayaudio")' in source
        and "routeWarning ? AnyShapeStyle(Color.orange)" in source
        and "routeWarning ? Color.orange" in source
    )
    for expected in replacements.values():
        if expected not in source and not pipeline_route_warning and not (
            path.name == "PipelineView.swift" and
            expected.replace("routeChangeBurst", "routeChangeBurst || carAudioSpeakerBounce") in source
        ):
            raise SystemExit(f"Expected upstream adaptation missing: {path}: {expected}")
    path.write_text(source)

# Keep upstream logic tests aligned with the app's brand while preserving the
# same route-name, case-folding, containment, and user-copy assertions.
test_changes = {
    root / "Tests/Unit/FeedbackLoopTests.swift": {
        'XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: "EffectDeck"))':
        'XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: ETAudioSessionRules.nameStem))',
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: "effectdeck"))\n'
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: "EFFECTDECK"))\n'
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: "eFfEcTdEcK"))':
        '        let stem = ETAudioSessionRules.nameStem\n'
        '        let mixedCase = String(stem.enumerated().map { index, character in\n'
        '            index.isMultiple(of: 2) ? String(character).lowercased() : String(character).uppercased()\n'
        '        }.joined())\n'
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: stem.lowercased()))\n'
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: stem.uppercased()))\n'
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: mixedCase))',
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: "EffectDeck (2)"))\n'
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: "iPhone → EffectDeck"))\n'
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: "My EffectDeck Bridge"))':
        '        let stem = ETAudioSessionRules.nameStem\n'
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: "\\(stem) (2)"))\n'
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: "iPhone → \\(stem)"))\n'
        '        XCTAssertTrue(ETAudioSessionRules.isOwnDevice(portName: "My \\(stem) Bridge"))',
    },
    root / "Tests/Unit/NowPlayingModeTests.swift": {
        'XCTAssertEqual(ETNowPlayingText.title, "EffectDeck")':
        'XCTAssertEqual(ETNowPlayingText.title, "Sonance EQ")',
    },
    root / "Tests/Unit/OutputDeviceTests.swift": {
        '        XCTAssertNil(ETOutputDevice.pick([spk, dev(.other, "EffectDeck")]))\n'
        '        XCTAssertNil(ETOutputDevice.pick([dev(.other, "effectdeck")]))\n'
        '        XCTAssertNil(ETOutputDevice.pick([dev(.other, "EffectDeck"), bt]))':
        '        let ownRoute = ETAudioSessionRules.nameStem\n'
        '        XCTAssertNil(ETOutputDevice.pick([spk, dev(.other, ownRoute)]))\n'
        '        XCTAssertNil(ETOutputDevice.pick([dev(.other, ownRoute.lowercased())]))\n'
        '        XCTAssertNil(ETOutputDevice.pick([dev(.other, ownRoute), bt]))',
    },
    root / "Tests/Unit/StatusReadingsTests.swift": {
        '"Pick EffectDeck as the output in Control Center."':
        '"No audio is reaching Sonance EQ. If the player says it does not support EffectDeck Audio or Sonance EQ Audio, it cannot send audio to that route. Choose CarPlay directly for car audio, or use a compatible player or local file for EQ. If audio switches back without that message, tap Help."',
    },
}
for path, replacements in test_changes.items():
    source = path.read_text()
    for old, new in replacements.items():
        if old in source:
            source = source.replace(old, new)
        if new not in source:
            raise SystemExit(f"Expected branded test adaptation missing: {path}: {new}")
    path.write_text(source)

# These are structural insertions: their old text remains a substring of the
# inserted text, so keep them separate from global replacements and guard each
# with a unique new-source marker to make repeated project generation safe.
pipeline = root / "Sources/EffeTuneLive/Views/PipelineView.swift"
source = pipeline.read_text()
source = source.replace(
    'Audio left Sonance EQ for \\(currentRoute)',
    'Audio left the EQ route for \\(currentRoute)')
source = source.replace(
    'iOS moved audio away from Sonance EQ to \\(currentRoute). Playback is now outside the EQ chain. If SoundCloud says Sonance EQ Audio is unsupported, keep CarPlay selected; that player cannot send audio to this route. With a compatible source, select Sonance EQ once in Control Center and resume. iOS controls route selection, so Sonance EQ cannot force the route.',
    'iOS moved audio away from the EQ route to \\(currentRoute). Playback is now outside the EQ chain. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, keep CarPlay selected; that player cannot send audio to this route. With a compatible source, select the EQ route once in Control Center and resume. iOS controls route selection, so Sonance EQ cannot force the route.')
route_title = '        if routeReturnedFromSonanceEQ { return "Audio left the EQ route for \\(currentRoute)" }'
source = source.replace(route_title + '\n' + route_title, route_title)
route_instruction = (
    '        if routeReturnedFromSonanceEQ {\n'
    '            return "iOS moved playback from Sonance EQ to this output; that handoff alone does not mean the EQ is faulty. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, stop retrying that route. Keep CarPlay selected for car audio (EQ is bypassed), or use a compatible player / local file for EQ. Sonance EQ cannot override iOS route selection."\n'
    '        }')
existing_route_instruction = (
    '        if routeReturnedFromSonanceEQ {\n'
    '            return "Playback is now outside the EQ chain. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, it rejected the route. Keep CarPlay selected for car audio (EQ is bypassed), or use a compatible player / local file for EQ. Re-selecting the route cannot fix an unsupported source; iOS controls route selection."\n'
    '        }')
source = source.replace(existing_route_instruction, route_instruction)
source = source.replace(route_instruction + '\n' + route_instruction, route_instruction)
source = source.replace(
    '            let transition = lastRouteChange.isEmpty ? "Current output: \\(currentRoute)." : "Last route change: \\(lastRouteChange)."\n'
    '            return "\\(transition) Playback is now outside the EQ chain. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, it rejected the route; keep CarPlay selected for car audio or use a compatible player / local file in Sonance EQ. Re-selecting the route cannot fix an unsupported source. iOS controls route selection, so Sonance EQ cannot force the route."',
    '            return "Playback is now outside the EQ chain. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, it rejected the route. Keep CarPlay selected for car audio (EQ is bypassed), or use a compatible player / local file for EQ. Re-selecting the route cannot fix an unsupported source; iOS controls route selection."')
source = source.replace(
    '            return "iOS changed the audio route several times in 30 seconds. Last change: \\(lastRouteChange). Leave the current route selected instead of repeatedly switching. If SoundCloud says this route is unsupported, use CarPlay directly or play a local file in Sonance EQ."',
    '            return "iOS changed the audio route several times in 30 seconds. Leave the current route selected instead of repeatedly switching. For car audio, choose CarPlay directly (EQ is bypassed); for EQ, use a compatible player or local file."')
source = source.replace(
    '            return "iOS changed the audio route several times in 30 seconds. Leave the current route selected instead of repeatedly switching. For car audio, choose CarPlay directly (EQ is bypassed); for EQ, use a compatible player or local file."',
    '            return "iOS changed the audio route several times in 30 seconds. Last change: \\(lastRouteChange). Stop toggling between routes. For car audio, leave CarPlay selected (EQ is bypassed); for EQ, use a compatible player or local file."')
old_route_return = (
    '        if routeReturnedFromSonanceEQ {\n'
    '            return "iOS moved audio away from the EQ route to \\(currentRoute). Playback is now outside the EQ chain. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, keep CarPlay selected; that player cannot send audio to this route. With a compatible source, select the EQ route once in Control Center and resume. iOS controls route selection, so Sonance EQ cannot force the route."\n'
    '        }\n')
source = source.replace(old_route_return, '')

# Preserve a single route-rejection transition, even when it does not repeat
# enough times to trip the burst detector. This is diagnostic only: iOS owns
# output selection and an incompatible source app cannot be forced onto it.
audio_io = root / "Sources/EffeTuneLive/Audio/AudioIO.swift"
audio_source = audio_io.read_text()
if '@Published var routeReturnedFromSonanceEQ = false' not in audio_source:
    audio_source = audio_source.replace(
        '    @Published var routeFallback = false\n',
        '    @Published var routeFallback = false\n'
        '    /// iOS moved playback away from our route after it had been selected.\n'
        '    @Published var routeReturnedFromSonanceEQ = false\n', 1)
if 'previousWasOwnDevice: Bool' not in audio_source:
    audio_source = audio_source.replace(
        '                let previousIdentity = previousRoute?.outputs\n'
        '                    .map { "\\($0.portType.rawValue):\\($0.uid)" }\n'
        '                    .joined(separator: "|")\n',
        '                let previousIdentity = previousRoute?.outputs\n'
        '                    .map { "\\($0.portType.rawValue):\\($0.uid)" }\n'
        '                    .joined(separator: "|")\n'
        '                let previousRouteName = previousRoute?.outputs\n'
        '                    .map(\\.portName)\n'
        '                    .joined(separator: ", ")\n'
        '                let previousWasOwnDevice = previousRoute?.outputs.contains {\n'
        '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
        '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
        '                } ?? false\n', 1)
    audio_source = audio_source.replace(
        '                    self?.refreshRoute(reason: reason, previousIdentity: previousIdentity)\n',
        '                    self?.refreshRoute(reason: reason, previousIdentity: previousIdentity,\n'
        '                                       previousWasOwnDevice: previousWasOwnDevice,\n'
        '                                       previousRouteName: previousRouteName)\n', 1)
audio_source = audio_source.replace(
    '                let previousWasOwnDevice = previousRoute?.outputs.contains {\n'
    '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName)\n'
    '                } ?? false\n',
    '                let previousWasOwnDevice = previousRoute?.outputs.contains {\n'
    '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
    '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
    '                } ?? false\n', 1)
audio_source = audio_source.replace(
    '    private func refreshRoute(reason: UInt = 99, previousIdentity: String? = nil) {',
    '    private func refreshRoute(reason: UInt = 99, previousIdentity: String? = nil,\n'
    '                              previousWasOwnDevice: Bool = false,\n'
    '                              previousRouteName: String? = nil) {', 1)
if 'routeReturnedFromSonanceEQ = true' not in audio_source:
    audio_source = audio_source.replace(
        '        let nowRoute = outs.isEmpty ? "no output" : names\n',
        '        let nowEQRoute = outs.contains {\n'
        '            ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
        '                $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
        '        }\n'
        '        if nowEQRoute {\n'
        '            routeReturnedFromSonanceEQ = false\n'
        '        } else if reason != 99 && previousWasOwnDevice {\n'
        '            routeReturnedFromSonanceEQ = true\n'
        '        }\n'
        '        let nowLoopback = outs.contains { ETAudioSessionRules.isOwnDevice(portName: $0.portName) }\n'
        '        let nowRoute = outs.isEmpty ? "no output" : names\n', 1)
    audio_source = audio_source.replace(
        '        let nowLoopback = outs.contains { ETAudioSessionRules.isOwnDevice(portName: $0.portName) }\n'
        '        if loopback != nowLoopback { loopback = nowLoopback }',
        '        if loopback != nowLoopback { loopback = nowLoopback }', 1)
audio_io.write_text(audio_source)

if '@State private var outputRoute = "—"' not in source:
    source = source.replace(
        '    @State private var restartNeeded = false\n',
        '    @State private var restartNeeded = false\n    @State private var outputRoute = "—"\n', 1)
if '@State private var routeFallback = false' not in source:
    source = source.replace(
        '    @State private var outputRoute = "—"\n',
        '    @State private var outputRoute = "—"\n    @State private var routeFallback = false\n', 1)
if '@State private var routeReturnedFromSonanceEQ = false' not in source:
    source = source.replace('    @State private var routeFallback = false\n',
                            '    @State private var routeFallback = false\n    @State private var routeReturnedFromSonanceEQ = false\n', 1)
if '@State private var carAudioActive = false' not in source:
    source = source.replace(
        '    @State private var routeFallback = false\n',
        '    @State private var routeFallback = false\n    @State private var carAudioActive = false\n', 1)
if '@State private var lastRouteChange = ""' not in source:
    source = source.replace(
        '    @State private var routeFallback = false\n',
        '    @State private var routeFallback = false\n    @State private var lastRouteChange = ""\n', 1)
if '@State private var routeChangeBurst = false' not in source:
    source = source.replace(
        '    @State private var lastRouteChange = ""\n',
        '    @State private var lastRouteChange = ""\n    @State private var routeChangeBurst = false\n', 1)

if 'outputRoute = io.outputRoute' not in source:
    source = source.replace('            restartNeeded = io.restartNeeded\n',
                            '            restartNeeded = io.restartNeeded\n            outputRoute = io.outputRoute\n', 1)
if 'routeFallback = io.routeFallback' not in source:
    source = source.replace('            outputRoute = io.outputRoute\n',
                            '            outputRoute = io.outputRoute\n            routeFallback = io.routeFallback\n', 1)
if 'routeReturnedFromSonanceEQ = io.routeReturnedFromSonanceEQ' not in source:
    source = source.replace('            routeFallback = io.routeFallback\n',
                            '            routeFallback = io.routeFallback\n            routeReturnedFromSonanceEQ = io.routeReturnedFromSonanceEQ\n', 1)
if 'carAudioActive = io.carAudioActive' not in source:
    source = source.replace('            routeFallback = io.routeFallback\n',
                            '            routeFallback = io.routeFallback\n            carAudioActive = io.carAudioActive\n', 1)
if 'lastRouteChange = io.lastRouteChange' not in source:
    source = source.replace('            routeFallback = io.routeFallback\n',
                            '            routeFallback = io.routeFallback\n            lastRouteChange = io.lastRouteChange\n', 1)
if 'routeChangeBurst = io.routeChangeBurst' not in source:
    source = source.replace('            lastRouteChange = io.lastRouteChange\n',
                            '            lastRouteChange = io.lastRouteChange\n            routeChangeBurst = io.routeChangeBurst\n', 1)

if '.onReceive(io.$outputRoute)' not in source:
    source = source.replace('        .onReceive(io.$restartNeeded) { restartNeeded = $0 }\n',
                            '        .onReceive(io.$restartNeeded) { restartNeeded = $0 }\n        .onReceive(io.$outputRoute) { outputRoute = $0 }\n', 1)
if '.onReceive(io.$routeFallback)' not in source:
    source = source.replace('        .onReceive(io.$outputRoute) { outputRoute = $0 }\n',
                            '        .onReceive(io.$outputRoute) { outputRoute = $0 }\n        .onReceive(io.$routeFallback) { routeFallback = $0 }\n', 1)
if '.onReceive(io.$routeReturnedFromSonanceEQ)' not in source:
    source = source.replace('        .onReceive(io.$routeFallback) { routeFallback = $0 }\n',
                            '        .onReceive(io.$routeFallback) { routeFallback = $0 }\n'
                            '        .onReceive(io.$routeReturnedFromSonanceEQ) { routeReturnedFromSonanceEQ = $0 }\n', 1)
if '.onReceive(io.$carAudioActive)' not in source:
    source = source.replace('        .onReceive(io.$routeFallback) { routeFallback = $0 }\n',
                            '        .onReceive(io.$routeFallback) { routeFallback = $0 }\n        .onReceive(io.$carAudioActive) { carAudioActive = $0 }\n', 1)
if '.onReceive(io.$lastRouteChange)' not in source:
    source = source.replace('        .onReceive(io.$routeFallback) { routeFallback = $0 }\n',
                            '        .onReceive(io.$routeFallback) { routeFallback = $0 }\n        .onReceive(io.$lastRouteChange) { lastRouteChange = $0 }\n', 1)
if '.onReceive(io.$routeChangeBurst)' not in source:
    source = source.replace('        .onReceive(io.$lastRouteChange) { lastRouteChange = $0 }\n',
                            '        .onReceive(io.$lastRouteChange) { lastRouteChange = $0 }\n        .onReceive(io.$routeChangeBurst) { routeChangeBurst = $0 }\n', 1)

banner_call = 'ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, routeFallback: routeFallback, routeReturnedFromSonanceEQ: routeReturnedFromSonanceEQ, carAudioActive: carAudioActive, routeChangeBurst: routeChangeBurst, lastRouteChange: lastRouteChange, openTips: { presentSheet(.tips) })'
source = source.replace(
    'ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, routeFallback: routeFallback, carAudioActive: carAudioActive, routeChangeBurst: routeChangeBurst, lastRouteChange: lastRouteChange, openTips: { presentSheet(.tips) })',
    banner_call)
source = source.replace(
    '} else if !hasPeer || routeChangeBurst {',
    '} else if !hasPeer || routeChangeBurst || routeReturnedFromSonanceEQ {')
source = source.replace(
    '} else if !hasPeer || routeChangeBurst || routeReturnedFromSonanceEQ {',
    '} else if ETRouteStatusPresentation.shouldDisplayBanner(\n'
    '                hasPeer: hasPeer,\n'
    '                routeFallback: routeFallback,\n'
    '                routeReturnedFromSonanceEQ: routeReturnedFromSonanceEQ,\n'
    '                carAudioActive: carAudioActive,\n'
    '                routeChangeBurst: routeChangeBurst) {')
source = source.replace('ConnectBanner(restartNeeded: restartNeeded, openTips: { presentSheet(.tips) })', banner_call)
source = source.replace('ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, openTips: { presentSheet(.tips) })', banner_call)
source = source.replace('ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, routeFallback: routeFallback, openTips: { presentSheet(.tips) })', banner_call)
source = source.replace('ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, routeFallback: routeFallback, lastRouteChange: lastRouteChange, openTips: { presentSheet(.tips) })', banner_call)
source = source.replace('ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, routeFallback: routeFallback, routeChangeBurst: routeChangeBurst, lastRouteChange: lastRouteChange, openTips: { presentSheet(.tips) })', banner_call)
if banner_call not in source and 'carAudioSpeakerBounce: carAudioSpeakerBounce' not in source:
    raise SystemExit(f"Expected route-aware banner call missing: {pipeline}")

if '    let currentRoute: String' not in source:
    source = source.replace('    let restartNeeded: Bool\n',
                            '    let restartNeeded: Bool\n    let currentRoute: String\n', 1)
if '    let routeFallback: Bool' not in source:
    source = source.replace('    let currentRoute: String\n',
                            '    let currentRoute: String\n    let routeFallback: Bool\n', 1)
if '    let routeReturnedFromSonanceEQ: Bool' not in source:
    source = source.replace('    let routeFallback: Bool\n',
                            '    let routeFallback: Bool\n    let routeReturnedFromSonanceEQ: Bool\n', 1)
if '    let carAudioActive: Bool' not in source:
    source = source.replace('    let routeFallback: Bool\n',
                            '    let routeFallback: Bool\n    let carAudioActive: Bool\n', 1)
if '    let lastRouteChange: String' not in source:
    source = source.replace('    let routeFallback: Bool\n',
                            '    let routeFallback: Bool\n    let lastRouteChange: String\n', 1)
if '    let routeChangeBurst: Bool' not in source:
    source = source.replace('    let routeFallback: Bool\n',
                            '    let routeFallback: Bool\n    let routeChangeBurst: Bool\n', 1)
if 'Text("Current output seen by Sonance EQ:' not in source:
    needle = ('                    Text(instruction)\n'
              '                        .etFont(size: 12)\n'
              '                        .foregroundStyle(.secondary)\n'
              '                        .fixedSize(horizontal: false, vertical: true)')
    addition = (needle + '\n'
                '                    if !currentRoute.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, currentRoute != "—" {\n'
                '                        Text("Current output seen by Sonance EQ: \\(currentRoute)")\n'
                '                            .etFont(size: 11)\n'
                '                            .foregroundStyle(.secondary)\n'
                '                            .fixedSize(horizontal: false, vertical: true)\n'
                '                    }')
    if needle not in source:
        raise SystemExit(f"Expected route status insertion point missing: {pipeline}")
    source = source.replace(needle, addition, 1)
if 'Text("Recent route changes:' not in source:
    needle = ('                        Text("Current output seen by Sonance EQ: \\(currentRoute)")\n'
              '                            .etFont(size: 11)\n'
              '                            .foregroundStyle(.secondary)\n'
              '                            .fixedSize(horizontal: false, vertical: true)\n'
              '                    }')
    addition = (needle + '\n'
                '                    if !lastRouteChange.isEmpty {\n'
                '                        Text("Recent route changes:\\n\\(lastRouteChange)")\n'
                '                            .etFont(size: 11)\n'
                '                            .foregroundStyle(.secondary)\n'
                '                            .fixedSize(horizontal: false, vertical: true)\n'
                '                    }')
    if needle not in source:
        raise SystemExit(f"Expected route transition insertion point missing: {pipeline}")
    source = source.replace(needle, addition, 1)

if 'ETRouteDiagnosticReport.make(' not in source:
    needle = ('                        Text("Recent route changes:\\n\\(lastRouteChange)")\n'
              '                            .etFont(size: 11)\n'
              '                            .foregroundStyle(.secondary)\n'
              '                            .fixedSize(horizontal: false, vertical: true)\n'
              '                    }')
    addition = (needle + '\n'
                '                    ShareLink(item: ETRouteDiagnosticReport.make(\n'
                '                        appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",\n'
                '                        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",\n'
                '                        osVersion: UIDevice.current.systemVersion,\n'
                '                        currentOutput: currentRoute,\n'
                '                        routeFallback: routeFallback,\n'
                '                        routeReturnedFromSonanceEQ: routeReturnedFromSonanceEQ,\n'
                '                        carAudioActive: carAudioActive,\n'
                '                        routeChangeBurst: routeChangeBurst,\n'
                '                        carAudioSpeakerBounce: carAudioSpeakerBounce,\n'
                '                        carAudioEQBounce: carAudioEQBounce,\n'
                '                        recentChanges: lastRouteChange)) {\n'
                '                        Label("Share route report", systemImage: "square.and.arrow.up")\n'
                '                            .etFont(size: 12, weight: .semibold)\n'
                '                    }\n'
                '                    .buttonStyle(.bordered)\n'
                '                    .accessibilityIdentifier("shareRouteReport")')
    if needle not in source:
        raise SystemExit(f"Expected route report insertion point missing: {pipeline}")
    source = source.replace(needle, addition, 1)

# Make an observed return to the built-in speaker explicit. Car audio is a
# valid direct output and gets a separate informational status. The
# route picker itself remains owned by iOS Control Center; this is diagnosis,
# not a private or silent route-selection attempt.
if 'return routeFallback ? "Output is on \\(currentRoute)"' not in source:
    source = source.replace(
        '        restartNeeded ? "\\(UIDevice.current.model) Restart Required" : "No audio yet"',
        '        if restartNeeded { return "\\(UIDevice.current.model) Restart Required" }\n'
        '        return routeFallback ? "Output is on \\(currentRoute)" : "No audio yet"', 1)
if 'if routeChangeBurst { return "Audio route keeps changing" }' not in source:
    source = source.replace(
        '        return routeFallback ? "Output is on \\(currentRoute)" : "No audio yet"',
        '        if routeChangeBurst { return "Audio route keeps changing" }\n'
        '        return routeFallback ? "Output is on \\(currentRoute)" : "No audio yet"', 1)
if 'if routeReturnedFromSonanceEQ { return "Audio left the EQ route for \\(currentRoute)" }' not in source:
    source = source.replace(
        '        if routeChangeBurst { return "Audio route keeps changing" }',
        '        if routeReturnedFromSonanceEQ { return "Audio left the EQ route for \\(currentRoute)" }\n'
        '        if routeChangeBurst { return "Audio route keeps changing" }', 1)
source = source.replace(
    '(restartNeeded || routeFallback || routeChangeBurst) ? "exclamationmark.triangle.fill" : "airplayaudio"',
    '(restartNeeded || routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst) ? "exclamationmark.triangle.fill" : "airplayaudio"')
source = source.replace(
    '(routeFallback || routeChangeBurst) ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint)',
    '(routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst) ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint)')
source = source.replace(
    '(routeFallback || routeChangeBurst) ? Color.orange : Color.primary',
    '(routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst) ? Color.orange : Color.primary')
source = source.replace(
    'if routeReturnedFromSonanceEQ { return "Audio left Sonance EQ for \\(currentRoute)" }',
    'if routeReturnedFromSonanceEQ { return "Audio left the EQ route for \\(currentRoute)" }')
source = source.replace(
    'iOS moved audio away from Sonance EQ to \\(currentRoute). Playback is now outside the EQ chain. If SoundCloud says Sonance EQ Audio is unsupported, keep CarPlay selected; that player cannot send audio to this route. With a compatible source, select Sonance EQ once in Control Center and resume. iOS controls route selection, so Sonance EQ cannot force the route.',
    'iOS moved audio away from the EQ route to \\(currentRoute). Playback is now outside the EQ chain. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, keep CarPlay selected; that player cannot send audio to this route. With a compatible source, select the EQ route once in Control Center and resume. iOS controls route selection, so Sonance EQ cannot force the route.')
if 'if carAudioActive { return "Output is routed to car audio" }' not in source:
    source = source.replace(
        '        return routeFallback ? "Output is on \\(currentRoute)" : "No audio yet"',
        '        if carAudioActive { return "Output is routed to car audio" }\n'
        '        return routeFallback ? "Output is on \\(currentRoute)" : "No audio yet"', 1)
if 'private var instruction: String {\n        restartNeeded\n' in source:
    source = source.replace(
        '            } else if !hasPeer {\n                ConnectBanner(',
        '            } else if ETRouteStatusPresentation.shouldDisplayBanner(\n'
        '                hasPeer: hasPeer,\n'
        '                routeFallback: routeFallback,\n'
        '                routeReturnedFromSonanceEQ: routeReturnedFromSonanceEQ,\n'
        '                carAudioActive: carAudioActive,\n'
        '                routeChangeBurst: routeChangeBurst) {\n'
        '                ConnectBanner(', 1)
    old_instructions = (
        '        restartNeeded\n'
        '            ? "Restart once after this update, then pick EffectDeck in Control Center."\n'
        '            : "Pick EffectDeck as the output in Control Center."',
        '        restartNeeded\n'
        '            ? "Restart once after this update, then pick Sonance EQ in Control Center."\n'
        '            : "Pick Sonance EQ as the output in Control Center."',
        '        restartNeeded\n'
        '            ? "Restart once after this update, then pick Sonance EQ in Control Center. Install Sonance EQ Route if it is not listed."\n'
        '            : "Pick Sonance EQ in Control Center. If audio switches to iPhone or CarPlay, select Sonance EQ again and resume playback. A player that says this route is unsupported cannot send audio here; use CarPlay directly or a supported player."',
        '        restartNeeded\n'
        '            ? "Restart once after this update, then pick Sonance EQ in Control Center."\n'
        '            : "Pick Sonance EQ as the output in Control Center. Install Sonance EQ Route if it is not listed. If the player says this route is unsupported, choose CarPlay directly or play a local file in Sonance EQ. If audio switches back without that message, tap Help."')
    new_instruction = (
        '        if restartNeeded {\n'
        '            return "Restart once after this update, then pick Sonance EQ in Control Center. Install Sonance EQ Route if it is not listed."\n'
        '        }\n'
        '        if routeFallback {\n'
        '            return "No source audio has reached Sonance EQ. Current output: \\(currentRoute). If the player rejected Sonance EQ Audio, stop retrying that route; use CarPlay directly or play a local file. Otherwise select Sonance EQ once in Control Center and resume."\n'
        '        }\n'
        '        if carAudioActive {\n'
        '            return "The current output is \\(currentRoute). Playback on this route bypasses Sonance EQ unless the source supports and selects the Sonance EQ route. If SoundCloud rejects it, keep CarPlay selected or use a compatible source."\n'
        '        }\n'
        '        return "Pick Sonance EQ in Control Center. If the player says this route is unsupported, use CarPlay directly or a compatible player."')
    for old_instruction in old_instructions:
        if old_instruction in source:
            source = source.replace(old_instruction, new_instruction, 1)
            break
    if 'if routeFallback {' not in source:
        raise SystemExit(f"Could not install route fallback diagnosis in {pipeline}")
if 'ETRouteStatusPresentation.make(' not in source:
    if 'Recent changes: \\(lastRouteChange)' not in source:
        source = source.replace(
            '        if routeFallback {\n',
            '        if routeChangeBurst {\n'
            '            return "iOS changed the audio route several times in 30 seconds. Recent changes: \\(lastRouteChange). Stop toggling between routes. For car audio, leave CarPlay selected (EQ is bypassed); for EQ, use a compatible player or local file."\n'
            '        }\n'
            '        if routeFallback {\n', 1)
        if 'Recent changes: \\(lastRouteChange)' not in source:
            raise SystemExit(f"Could not install route burst explanation in {pipeline}")
    if 'iOS moved playback from Sonance EQ to this output' not in source:
        source = source.replace(
            '        if routeChangeBurst {\n',
            '        if routeReturnedFromSonanceEQ {\n'
            '            return "iOS moved playback from Sonance EQ to this output; that handoff alone does not mean the EQ is faulty. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, stop retrying that route. Keep CarPlay selected for car audio (EQ is bypassed), or use a compatible player / local file for EQ. Sonance EQ cannot override iOS route selection."\n'
            '        }\n'
            '        if routeChangeBurst {\n', 1)
        if 'iOS moved playback from Sonance EQ to this output' not in source:
            raise SystemExit(f"Could not install single route-return diagnosis in {pipeline}")
    if 'Playback on this route bypasses Sonance EQ' not in source:
        source = source.replace(
        '            return "No source audio has reached Sonance EQ. Its current output is \\(currentRoute). Select Sonance EQ in Control Center and resume. If SoundCloud says this route is unsupported, use CarPlay directly or play a local file in Sonance EQ."',
        '            return "No source audio has reached Sonance EQ. Current output: \\(currentRoute). If the player rejected Sonance EQ Audio, stop retrying that route; use CarPlay directly or play a local file. Otherwise select Sonance EQ once in Control Center and resume."', 1)
    source = source.replace(
        '            return "No source audio has reached Sonance EQ. Current output: \\(currentRoute). If the player rejected Sonance EQ Audio, stop retrying that route; use CarPlay directly or play a local file. Otherwise select Sonance EQ once in Control Center and resume."\n'
        '        }\n'
        '        return "Pick Sonance EQ in Control Center. If the player says this route is unsupported, use CarPlay directly or a compatible player."',
        '            return "No source audio has reached Sonance EQ. Its current output is \\(currentRoute). Select Sonance EQ in Control Center and resume. If SoundCloud says this route is unsupported, use CarPlay directly or play a local file in Sonance EQ."\n'
        '        }\n'
        '        if carAudioActive {\n'
        '            return "The current output is \\(currentRoute). Playback on this route bypasses Sonance EQ unless the source supports and selects the Sonance EQ route. If SoundCloud rejects it, keep CarPlay selected or use a compatible source."\n'
        '        }\n'
        '        return "Pick Sonance EQ in Control Center. If the player says this route is unsupported, use CarPlay directly or a compatible player."', 1)
    source = source.replace(
        'return routeFallback ? "Output is on \\(currentRoute)" : "No audio yet"',
        'return routeFallback ? "Output is on \\(currentRoute)" : "No audio reached Sonance EQ"')
    source = source.replace(
        'return "Pick Sonance EQ in Control Center. If the player says this route is unsupported, use CarPlay directly or a compatible player."',
        'return "The current source has not sent audio to Sonance EQ. iOS and the source app decide whether this route is supported; Sonance EQ can report the route but cannot force it or read another app’s rejection alert. If SoundCloud says EffectDeck Audio is unsupported, stop retrying that route: keep CarPlay selected for car audio (EQ is bypassed), or play a local file in Sonance EQ. For a source that supports system routing, select Sonance EQ once in Control Center."')
    source = source.replace(
        'No source audio has reached Sonance EQ. Its current output is \\(currentRoute). Select Sonance EQ in Control Center and resume. If SoundCloud says this route is unsupported, use CarPlay directly or play a local file in Sonance EQ.',
        'No source audio has reached Sonance EQ. Current output: \\(currentRoute). If the player rejected Sonance EQ Audio, stop retrying that route; use CarPlay directly or play a local file. Otherwise select Sonance EQ once in Control Center and resume.')
    source = source.replace(
        'iOS changed the audio route several times in 30 seconds. The last change was: \\(lastRouteChange). Select Sonance EQ once in Control Center. If the player says this route is unsupported, it cannot send audio to Sonance EQ; use CarPlay directly or play a local file in Sonance EQ.',
        'iOS changed the audio route several times in 30 seconds. Recent changes: \\(lastRouteChange). Leave the current route selected instead of repeatedly switching. If SoundCloud says this route is unsupported, use CarPlay directly or play a local file in Sonance EQ.')
    source = source.replace(
        '    /// iOS returned playback to the built-in speaker or car-audio route while no source link is active.',
        '    /// iOS returned playback to the built-in speaker while no source link is active.')
pipeline.write_text(source)

audio_io = root / "Sources/EffeTuneLive/Audio/AudioIO.swift"
source = audio_io.read_text()
source = source.replace(
    '    /// iOS returned playback to the built-in speaker or car-audio route while no source link is active.',
    '    /// iOS returned playback to the built-in speaker while no source link is active.')
if "@Published var routeFallback = false" not in source:
    source = source.replace(
        '    @Published var outputRoute: String = "—"\n',
        '    @Published var outputRoute: String = "—"\n'
        '    /// iOS returned playback to the built-in speaker while no source link is active.\n'
        '    @Published var routeFallback = false\n', 1)
old_fallback = (
    '        let nowRouteIsFallback = outs.contains {\n'
    '            $0.portType == .builtInSpeaker || $0.portType == .carAudio\n'
    '        }\n'
    '        if routeFallback != nowRouteIsFallback { routeFallback = nowRouteIsFallback }\n')
if old_fallback in source:
    source = source.replace(
        old_fallback,
        '        let nowRouteIsFallback = outs.contains { $0.portType == .builtInSpeaker }\n'
        '        if routeFallback != nowRouteIsFallback { routeFallback = nowRouteIsFallback }\n'
        '        let nowRouteIsCarAudio = outs.contains { $0.portType == .carAudio }\n'
        '        if carAudioActive != nowRouteIsCarAudio { carAudioActive = nowRouteIsCarAudio }\n', 1)
if "let nowRouteIsFallback" not in source:
    source = source.replace(
        '        let nowRoute = outs.isEmpty ? "no output" : names\n',
        '        let nowRoute = outs.isEmpty ? "no output" : names\n'
        '        let nowRouteIsFallback = outs.contains { $0.portType == .builtInSpeaker }\n'
        '        if routeFallback != nowRouteIsFallback { routeFallback = nowRouteIsFallback }\n'
        '        let nowRouteIsCarAudio = outs.contains { $0.portType == .carAudio }\n'
        '        if carAudioActive != nowRouteIsCarAudio { carAudioActive = nowRouteIsCarAudio }\n', 1)
if "let nowRouteIsCarAudio" not in source:
    source = source.replace(
        '        let nowRouteIsFallback = outs.contains { $0.portType == .builtInSpeaker }\n'
        '        if routeFallback != nowRouteIsFallback { routeFallback = nowRouteIsFallback }\n',
        '        let nowRouteIsFallback = outs.contains { $0.portType == .builtInSpeaker }\n'
        '        if routeFallback != nowRouteIsFallback { routeFallback = nowRouteIsFallback }\n'
        '        let nowRouteIsCarAudio = outs.contains { $0.portType == .carAudio }\n'
        '        if carAudioActive != nowRouteIsCarAudio { carAudioActive = nowRouteIsCarAudio }\n', 1)
if "@Published var carAudioActive = false" not in source:
    source = source.replace(
        '    @Published var routeFallback = false\n',
        '    @Published var routeFallback = false\n'
        '    /// The active output is car audio; playback on it bypasses this host.\n'
        '    @Published var carAudioActive = false\n', 1)
if "@Published var lastRouteChange = \"\"" not in source:
    source = source.replace(
        '    @Published var routeFallback = false\n',
        '    @Published var routeFallback = false\n'
        '    /// Last AVAudioSession output transition observed while the source link is missing.\n'
        '    @Published var lastRouteChange = ""\n', 1)
if "@Published var routeChangeBurst = false" not in source:
    source = source.replace(
        '    @Published var lastRouteChange = ""\n',
        '    @Published var lastRouteChange = ""\n'
        '    /// True after at least three route transitions arrive within 30 seconds.\n'
        '    @Published var routeChangeBurst = false\n'
        '    private var routeChangeTimes: [TimeInterval] = []\n', 1)
if 'private var routeChangeHistory = ETRouteChangeHistory()' not in source:
    source = source.replace(
        '    @Published var lastRouteChange = ""\n',
        '    @Published var lastRouteChange = ""\n'
        '    private var routeChangeHistory = ETRouteChangeHistory()\n', 1)
if 'static func routeChangeReasonName' not in source:
    source = source.replace(
        '    /// 出力先の見直し。route / outputRoute / loopback は同じ 1 回の問い合わせから作る。\n',
        '    private static func routeChangeReasonName(_ reason: UInt) -> String {\n'
        '        switch reason {\n'
        '        case 0: return "unknown reason"\n'
        '        case 1: return "new device available"\n'
        '        case 2: return "old device unavailable"\n'
        '        case 3: return "audio category changed"\n'
        '        case 4: return "output override"\n'
        '        case 6: return "wake from sleep"\n'
        '        case 7: return "no suitable route"\n'
        '        case 8: return "route configuration changed"\n'
        '        default: return "system reason \\(reason)"\n'
        '        }\n'
        '    }\n\n'
        '    /// 出力先の見直し。route / outputRoute / loopback は同じ 1 回の問い合わせから作る。\n', 1)
if 'routeChangeTimes = routeChangeTimes.filter' not in source:
    source = source.replace(
        '        if route != nowRoute {\n',
        '        if route != nowRoute {\n'
        '            if reason != 99 && route != "—" {\n'
        '                let now = ProcessInfo.processInfo.systemUptime\n'
        '                routeChangeTimes = routeChangeTimes.filter { now - $0 <= 30 }\n'
        '                routeChangeTimes.append(now)\n'
        '                routeChangeBurst = routeChangeTimes.count >= 3\n'
        '                let reasonName = Self.routeChangeReasonName(reason)\n'
        '                lastRouteChange = "\\(route) → \\(nowRoute) (\\(reasonName))"\n'
        '            }\n', 1)
if 'let currentUptime = ProcessInfo.processInfo.systemUptime' not in source:
    source = source.replace(
        '        let nowOutput = names.isEmpty ? "—" : names\n',
        '        let currentUptime = ProcessInfo.processInfo.systemUptime\n'
        '        routeChangeTimes = routeChangeTimes.filter { currentUptime - $0 <= 30 }\n'
        '        let recentRouteChanges = routeChangeTimes.count >= 3\n'
        '        if routeChangeBurst != recentRouteChanges { routeChangeBurst = recentRouteChanges }\n'
        '        let nowOutput = names.isEmpty ? "—" : names\n', 1)
# Identify route endpoints by port type and UID, not just the localized port
# name. Also use the previousRoute snapshot from the notification: the regular
# route refresh can observe a change before the notification handler runs.
if 'private var lastRouteIdentity = ""' not in source:
    source = source.replace(
        '    private var routeChangeTimes: [TimeInterval] = []\n',
        '    private var routeChangeTimes: [TimeInterval] = []\n'
        '    /// Names are for display; UIDs and port types identify actual route endpoints.\n'
        '    private var lastRouteIdentity = ""\n', 1)
if 'previousIdentity: String?' not in source:
    source = source.replace(
        '                let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 99\n'
        '                Task { @MainActor in self?.refreshRoute(reason: reason) }',
        '                let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 99\n'
        '                let previousRoute = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]\n'
        '                    as? AVAudioSessionRouteDescription\n'
        '                let previousIdentity = previousRoute?.outputs\n'
        '                    .map { "\\($0.portType.rawValue):\\($0.uid)" }\n'
        '                    .joined(separator: "|")\n'
        '                let previousRouteName = previousRoute?.outputs\n'
        '                    .map(\\.portName)\n'
        '                    .joined(separator: ", ")\n'
        '                let previousWasOwnDevice = previousRoute?.outputs.contains {\n'
        '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
        '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
        '                } ?? false\n'
        '                Task { @MainActor in\n'
        '                    self?.refreshRoute(reason: reason, previousIdentity: previousIdentity,\n'
        '                                       previousWasOwnDevice: previousWasOwnDevice,\n'
        '                                       previousRouteName: previousRouteName)\n'
        '                }', 1)
source = source.replace(
    '    private func refreshRoute(reason: UInt = 99) {',
    '    private func refreshRoute(reason: UInt = 99, previousIdentity: String? = nil,\n'
    '                              previousWasOwnDevice: Bool = false,\n'
    '                              previousRouteName: String? = nil) {', 1)
if 'let identity = outs.map' not in source:
    source = source.replace(
        '        let names = outs.map(\\.portName).joined(separator: ", ")\n',
        '        let names = outs.map(\\.portName).joined(separator: ", ")\n'
        '        let identity = outs.map { "\\($0.portType.rawValue):\\($0.uid)" }.joined(separator: "|")\n', 1)
old_route_change_block = (
    '        if route != nowRoute {\n'
    '            if reason != 99 && route != "—" {\n'
    '                let now = ProcessInfo.processInfo.systemUptime\n'
    '                routeChangeTimes = routeChangeTimes.filter { now - $0 <= 30 }\n'
    '                routeChangeTimes.append(now)\n'
    '                routeChangeBurst = routeChangeTimes.count >= 3\n'
    '                let reasonName = Self.routeChangeReasonName(reason)\n'
    '                lastRouteChange = "\\(route) → \\(nowRoute) (\\(reasonName))"\n'
    '            }\n')
new_route_change_block = (
    '        let changedByNotification = previousIdentity.map { $0 != identity }\n'
    '            ?? (!lastRouteIdentity.isEmpty && identity != lastRouteIdentity)\n'
    '        if reason != 99 && changedByNotification {\n'
    '            let now = ProcessInfo.processInfo.systemUptime\n'
    '            let reasonName = Self.routeChangeReasonName(reason)\n'
    '            // Use the route snapshot from the notification. A periodic refresh may\n'
    '            // already have updated `route` before this handler is scheduled.\n'
    '            let fromRoute = previousRouteName.flatMap { $0.isEmpty ? nil : $0 } ?? route\n'
    '            routeChangeHistory.record(from: fromRoute, to: nowRoute, reason: reasonName, at: now)\n'
    '            routeChangeBurst = routeChangeHistory.isBurst\n'
    '            lastRouteChange = routeChangeHistory.summary\n'
    '        }\n'
    '        if identity != lastRouteIdentity || route != nowRoute {\n')
if old_route_change_block in source:
    source = source.replace(old_route_change_block, new_route_change_block, 1)
source = source.replace('    private var routeChangeTimes: [TimeInterval] = []\n', '')
source = source.replace(
    '        routeChangeTimes = routeChangeTimes.filter { currentUptime - $0 <= 30 }\n'
    '        let recentRouteChanges = routeChangeTimes.count >= 3\n'
    '        if routeChangeBurst != recentRouteChanges { routeChangeBurst = recentRouteChanges }\n',
    '        routeChangeHistory.expire(at: currentUptime)\n'
    '        let recentRouteChanges = routeChangeHistory.isBurst\n'
    '        if routeChangeBurst != recentRouteChanges { routeChangeBurst = recentRouteChanges }\n'
    '        if lastRouteChange != routeChangeHistory.summary { lastRouteChange = routeChangeHistory.summary }\n')
if 'lastRouteIdentity = identity' not in source:
    source = source.replace('            route = nowRoute\n',
                            '            route = nowRoute\n            lastRouteIdentity = identity\n', 1)
if "@Published var routeFallback = false" not in source or "let nowRouteIsFallback" not in source:
    raise SystemExit(f"Expected route fallback observer missing: {audio_io}")
if "@Published var carAudioActive = false" not in source or "let nowRouteIsCarAudio" not in source:
    raise SystemExit(f"Expected car-audio route observer missing: {audio_io}")
if "@Published var lastRouteChange = \"\"" not in source or 'routeChangeHistory.record(from: fromRoute' not in source:
    raise SystemExit(f"Expected route transition diagnostic missing: {audio_io}")
if "@Published var routeChangeBurst = false" not in source or 'routeChangeHistory.isBurst' not in source:
    raise SystemExit(f"Expected route flap detector missing: {audio_io}")
audio_io.write_text(source)

# The host app is the combined product: expose the original Sonance player and
# the EffectDeck chain as sibling tabs. Keep the source project's screenshot
# probe path intact for its UI investigations.
host_app = root / "Sources/EffeTuneLive/EffeTuneLiveApp.swift"
source = host_app.read_text()
if "import SonanceEQPlayer" not in source:
    source = source.replace("import UIKit\n", "import UIKit\nimport SonanceEQPlayer\n", 1)
old_root = (
    '            Group {\n'
    '                // -ETProbe 1 のときは並べ替えの切り分け用の画面\n'
    '                // （ReorderProbeView.swift の頭）。\n'
    '                if ETScreenshotSeed.probe {\n'
    '                    ETReorderProbeView()\n'
    '                } else {\n'
    '                    PipelineView()\n'
    '                }\n'
    '            }')
new_root = (
    '            if ETScreenshotSeed.probe {\n'
    '                // -ETProbe 1 のときは並べ替えの切り分け用の画面\n'
    '                // （ReorderProbeView.swift の頭）。\n'
    '                ETReorderProbeView()\n'
    '            } else {\n'
    '                TabView(selection: $selectedTab) {\n'
    '                    SonancePlayerView()\n'
    '                        .tabItem { Label("Sonance EQ", systemImage: "slider.horizontal.3") }\n'
    '                        .tag("player")\n'
    '                    PipelineView(openLocalPlayer: { selectedTab = "player" })\n'
    '                        .tabItem { Label("Effects", systemImage: "point.3.connected.trianglepath.dotted") }\n'
    '                        .tag("effects")\n'
    '                }\n'
    '            }')
if old_root in source:
    source = source.replace(old_root, new_root, 1)
if '@State private var selectedTab = "player"' not in source:
    source = source.replace(
        '    @UIApplicationDelegateAdaptor(ETAppDelegate.self) private var appDelegate\n',
        '    @UIApplicationDelegateAdaptor(ETAppDelegate.self) private var appDelegate\n'
        '    @State private var selectedTab = "player"\n', 1)
if 'TabView(selection: $selectedTab)' not in source:
    source = source.replace('                TabView {\n', '                TabView(selection: $selectedTab) {\n', 1)
    source = source.replace(
        '                        .tabItem { Label("Sonance EQ", systemImage: "slider.horizontal.3") }\n'
        '                    PipelineView()\n',
        '                        .tabItem { Label("Sonance EQ", systemImage: "slider.horizontal.3") }\n'
        '                        .tag("player")\n'
        '                    PipelineView(openLocalPlayer: { selectedTab = "player" })\n', 1)
    source = source.replace(
        '                        .tabItem { Label("Effects", systemImage: "point.3.connected.trianglepath.dotted") }\n',
        '                        .tabItem { Label("Effects", systemImage: "point.3.connected.trianglepath.dotted") }\n'
        '                        .tag("effects")\n', 1)
if "import SonanceEQPlayer" not in source or "SonancePlayerView()" not in source or "PipelineView(openLocalPlayer:" not in source:
    raise SystemExit(f"Could not generate the combined Sonance and EffectDeck root: {host_app}")
host_app.write_text(source)

# The legacy picker route is still labeled EffectDeck on devices that already
# have that route installed. Treat either product label as the same EQ route
# for diagnosis, but only Sonance's own endpoint counts as an audio loopback.
audio_io = root / "Sources/EffeTuneLive/Audio/AudioIO.swift"
audio_source = audio_io.read_text()
old_route_observer = (
    '                let previousWasOwnDevice = previousRoute?.outputs.contains {\n'
    '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
    '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
    '                } ?? false\n'
    '                Task { @MainActor in\n'
    '                    self?.refreshRoute(reason: reason, previousIdentity: previousIdentity,\n'
    '                                       previousWasOwnDevice: previousWasOwnDevice,\n'
    '                                       previousRouteName: previousRouteName)\n'
    '                }')
new_route_observer = (
    '                let previousWasOwnDevice = previousRoute?.outputs.contains {\n'
    '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
    '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
    '                } ?? false\n'
    '                // Capture the destination while handling this notification. Deferring the\n'
    '                // read into a MainActor task can observe a later route after a fast\n'
    '                // CarPlay ↔ iPhone handoff and lose the intermediate transition.\n'
    '                let observedRoute = AVAudioSession.sharedInstance().currentRoute\n'
    '                let observedIdentity = observedRoute.outputs\n'
    '                    .map { "\\($0.portType.rawValue):\\($0.uid)" }\n'
    '                    .joined(separator: "|")\n'
    '                let observedRouteName = observedRoute.outputs\n'
    '                    .map(\\.portName)\n'
    '                    .joined(separator: ", ")\n'
    '                let observedIsEQRoute = observedRoute.outputs.contains {\n'
    '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
    '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
    '                }\n'
    '                Task { @MainActor in\n'
    '                    self?.refreshRoute(reason: reason, previousIdentity: previousIdentity,\n'
    '                                       previousWasOwnDevice: previousWasOwnDevice,\n'
    '                                       previousRouteName: previousRouteName,\n'
    '                                       observedIdentity: observedIdentity,\n'
    '                                       observedRouteName: observedRouteName,\n'
    '                                       observedIsEQRoute: observedIsEQRoute)\n'
    '                }')
if old_route_observer in audio_source:
    audio_source = audio_source.replace(old_route_observer, new_route_observer, 1)
audio_source = audio_source.replace(
    '                let observedRouteName = observedRoute.outputs\n'
    '                    .map(\\.portName)\n'
    '                    .joined(separator: ", ")\n'
    '                Task { @MainActor in\n',
    '                let observedRouteName = observedRoute.outputs\n'
    '                    .map(\\.portName)\n'
    '                    .joined(separator: ", ")\n'
    '                let observedIsEQRoute = observedRoute.outputs.contains {\n'
    '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
    '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
    '                }\n'
    '                Task { @MainActor in\n', 1)
audio_source = audio_source.replace(
    '                                       observedRouteName: observedRouteName)\n',
    '                                       observedRouteName: observedRouteName,\n'
    '                                       observedIsEQRoute: observedIsEQRoute)\n', 1)
if 'let observedRoute = AVAudioSession.sharedInstance().currentRoute' not in audio_source:
    raise SystemExit(f"Could not add route-notification snapshot capture: {audio_io}")
audio_source = audio_source.replace(
    '    private func refreshRoute(reason: UInt = 99, previousIdentity: String? = nil,\n'
    '                              previousWasOwnDevice: Bool = false,\n'
    '                              previousRouteName: String? = nil) {',
    '    private func refreshRoute(reason: UInt = 99, previousIdentity: String? = nil,\n'
    '                              previousWasOwnDevice: Bool = false,\n'
    '                              previousRouteName: String? = nil,\n'
    '                              observedIdentity: String? = nil,\n'
    '                              observedRouteName: String? = nil,\n'
    '                              observedIsEQRoute: Bool? = nil) {')
audio_source = audio_source.replace(
    '                              observedRouteName: String? = nil) {',
    '                              observedRouteName: String? = nil,\n'
    '                              observedIsEQRoute: Bool? = nil) {', 1)
audio_source = audio_source.replace(
    '        let changedByNotification = previousIdentity.map { $0 != identity }\n'
    '            ?? (!lastRouteIdentity.isEmpty && identity != lastRouteIdentity)\n',
    '        let eventIdentity = observedIdentity ?? identity\n'
    '        let eventRouteName = observedRouteName.flatMap { $0.isEmpty ? nil : $0 } ?? nowRoute\n'
    '        let changedByNotification = previousIdentity.map { $0 != eventIdentity }\n'
    '            ?? (!lastRouteIdentity.isEmpty && eventIdentity != lastRouteIdentity)\n')
audio_source = audio_source.replace(
    '            routeChangeHistory.record(from: fromRoute, to: nowRoute, reason: reasonName, at: now)\n',
    '            routeChangeHistory.record(from: fromRoute, to: eventRouteName, reason: reasonName, at: now)\n')
if 'let eventIdentity = observedIdentity ?? identity' not in audio_source:
    raise SystemExit(f"Could not use the route-notification snapshot in route history: {audio_io}")
old_route_state = (
    '        let nowLoopback = outs.contains { ETAudioSessionRules.isOwnDevice(portName: $0.portName) }\n'
    '        if nowLoopback {\n'
    '            routeReturnedFromSonanceEQ = false\n'
    '        } else if reason != 99 && previousWasOwnDevice {\n'
    '            routeReturnedFromSonanceEQ = true\n'
    '        }\n'
    '        let nowRoute = outs.isEmpty ? "no output" : names\n')
new_route_state = (
    '        let nowEQRoute = outs.contains {\n'
    '            ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
    '                $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
    '        }\n'
    '        let eventIsEQRoute = observedIsEQRoute ?? nowEQRoute\n'
    '        if eventIsEQRoute {\n'
    '            routeReturnedFromSonanceEQ = false\n'
    '        } else if reason != 99 && previousWasOwnDevice {\n'
    '            routeReturnedFromSonanceEQ = true\n'
    '        }\n'
    '        let nowLoopback = outs.contains { ETAudioSessionRules.isOwnDevice(portName: $0.portName) }\n'
    '        let nowRoute = outs.isEmpty ? "no output" : names\n')
if old_route_state in audio_source:
    audio_source = audio_source.replace(old_route_state, new_route_state, 1)
audio_source = audio_source.replace(
    '        if nowEQRoute {\n',
    '        let eventIsEQRoute = observedIsEQRoute ?? nowEQRoute\n'
    '        if eventIsEQRoute {\n', 1)
if 'let eventIsEQRoute = observedIsEQRoute ?? nowEQRoute' not in audio_source:
    raise SystemExit(f"Could not tie route return detection to the notification snapshot: {audio_io}")
audio_io.write_text(audio_source)

pipeline = root / "Sources/EffeTuneLive/Views/PipelineView.swift"
pipeline_source = pipeline.read_text()
pipeline_source = pipeline_source.replace(
    'Audio left Sonance EQ for \\(currentRoute)',
    'Audio left the EQ route for \\(currentRoute)')
pipeline_source = pipeline_source.replace(
    'iOS moved audio away from Sonance EQ to \\(currentRoute). Playback is now outside the EQ chain. If SoundCloud says Sonance EQ Audio is unsupported, keep CarPlay selected; that player cannot send audio to this route. With a compatible source, select Sonance EQ once in Control Center and resume. iOS controls route selection, so Sonance EQ cannot force the route.',
    'iOS moved audio away from the EQ route to \\(currentRoute). Playback is now outside the EQ chain. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, keep CarPlay selected; that player cannot send audio to this route. With a compatible source, select the EQ route once in Control Center and resume. iOS controls route selection, so Sonance EQ cannot force the route.')
# Keep the adaptation deterministic when starting from the pinned upstream
# archive. These declarations can be introduced in different phases above as
# older EffectDeck source versions are adapted.
if '@Published var routeReturnedFromSonanceEQ = false' not in audio_source:
    audio_source = audio_source.replace(
        '    @Published var routeFallback = false\n',
        '    @Published var routeFallback = false\n'
        '    /// iOS moved playback away from our route after it had been selected.\n'
        '    @Published var routeReturnedFromSonanceEQ = false\n', 1)
if '@Published var carAudioActive = false' not in audio_source:
    audio_source = audio_source.replace(
        '    @Published var routeReturnedFromSonanceEQ = false\n',
        '    @Published var routeReturnedFromSonanceEQ = false\n'
        '    /// The active output is car audio; playback on it bypasses this host.\n'
        '    @Published var carAudioActive = false\n', 1)
audio_source = audio_source.replace(
    '    @Published var routeFallback = false\n'
    '    /// Last AVAudioSession output transition observed while the source link is missing.\n'
    '    @Published var lastRouteChange = ""\n'
    '    private var routeChangeHistory = ETRouteChangeHistory()\n'
    '    /// True after at least three route transitions arrive within 30 seconds.\n'
    '    @Published var routeChangeBurst = false\n'
    '    /// Names are for display; UIDs and port types identify actual route endpoints.\n'
    '    private var lastRouteIdentity = ""\n',
    '    @Published var routeFallback = false\n'
    '    /// iOS moved playback away from our route after it had been selected.\n'
    '    @Published var routeReturnedFromSonanceEQ = false\n'
    '    /// The active output is car audio; playback on it bypasses this host.\n'
    '    @Published var carAudioActive = false\n'
    '    /// Last AVAudioSession output transition observed while the source link is missing.\n'
    '    @Published var lastRouteChange = ""\n'
    '    /// Bounded route evidence, separated from AVAudioSession so its window rules are testable.\n'
    '    private var routeChangeHistory = ETRouteChangeHistory()\n'
    '    /// True after at least three route transitions arrive within 30 seconds.\n'
    '    @Published var routeChangeBurst = false\n'
    '    /// Names are for display; UIDs and port types identify actual route endpoints.\n'
    '    private var lastRouteIdentity = ""\n')
audio_source = audio_source.replace(
    '    /// The active output is car audio; playback on it bypasses this host.\n'
    '    @Published var carAudioActive = false\n', '')
audio_source = audio_source.replace(
    '    @Published var routeReturnedFromSonanceEQ = false\n',
    '    @Published var routeReturnedFromSonanceEQ = false\n'
    '    /// The active output is car audio; playback on it bypasses this host.\n'
    '    @Published var carAudioActive = false\n', 1)
if '/// Bounded route evidence, separated from AVAudioSession so its window rules are testable.' not in audio_source:
    audio_source = audio_source.replace(
        '    private var routeChangeHistory = ETRouteChangeHistory()\n',
        '    /// Bounded route evidence, separated from AVAudioSession so its window rules are testable.\n'
        '    private var routeChangeHistory = ETRouteChangeHistory()\n', 1)
if '@Published var carAudioSpeakerBounce = false' not in audio_source:
    audio_source = audio_source.replace(
        '    @Published var routeChangeBurst = false\n',
        '    @Published var routeChangeBurst = false\n'
        '    /// Repeated transitions specifically between CarPlay and the iPhone speaker.\n'
        '    @Published var carAudioSpeakerBounce = false\n', 1)
if '@Published var carAudioEQBounce = false' not in audio_source:
    audio_source = audio_source.replace(
        '    @Published var carAudioSpeakerBounce = false\n',
        '    @Published var carAudioSpeakerBounce = false\n'
        '    /// Repeated transitions specifically between CarPlay and the Sonance EQ route.\n'
        '    @Published var carAudioEQBounce = false\n', 1)
if 'previousIsBuiltInSpeaker' not in audio_source:
    audio_source = audio_source.replace(
        '                let previousWasOwnDevice = previousRoute?.outputs.contains {\n'
        '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
        '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
        '                } ?? false\n',
        '                let previousWasOwnDevice = previousRoute?.outputs.contains {\n'
        '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
        '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
        '                } ?? false\n'
        '                let previousIsCarAudio = previousRoute?.outputs.contains { $0.portType == .carAudio } ?? false\n'
        '                let previousIsBuiltInSpeaker = previousRoute?.outputs.contains { $0.portType == .builtInSpeaker } ?? false\n', 1)
    audio_source = audio_source.replace(
        '                let observedIsEQRoute = observedRoute.outputs.contains {\n'
        '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
        '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
        '                }\n',
        '                let observedIsEQRoute = observedRoute.outputs.contains {\n'
        '                    ETAudioSessionRules.isOwnDevice(portName: $0.portName) ||\n'
        '                        $0.portName.localizedCaseInsensitiveContains("EffectDeck")\n'
        '                }\n'
        '                let observedIsCarAudio = observedRoute.outputs.contains { $0.portType == .carAudio }\n'
        '                let observedIsBuiltInSpeaker = observedRoute.outputs.contains { $0.portType == .builtInSpeaker }\n', 1)
    audio_source = audio_source.replace(
        '                                       observedIsEQRoute: observedIsEQRoute)\n',
        '                                       observedIsEQRoute: observedIsEQRoute,\n'
        '                                       previousIsCarAudio: previousIsCarAudio,\n'
        '                                       previousIsBuiltInSpeaker: previousIsBuiltInSpeaker,\n'
        '                                       observedIsCarAudio: observedIsCarAudio,\n'
        '                                       observedIsBuiltInSpeaker: observedIsBuiltInSpeaker)\n', 1)
    audio_source = audio_source.replace(
        '                              observedIsEQRoute: Bool? = nil) {',
        '                              observedIsEQRoute: Bool? = nil,\n'
        '                              previousIsCarAudio: Bool = false,\n'
        '                              previousIsBuiltInSpeaker: Bool = false,\n'
        '                              observedIsCarAudio: Bool? = nil,\n'
        '                              observedIsBuiltInSpeaker: Bool? = nil) {', 1)
    audio_source = audio_source.replace(
        '            routeChangeHistory.record(from: fromRoute, to: eventRouteName, reason: reasonName, at: now)\n'
        '            routeChangeBurst = routeChangeHistory.isBurst\n',
        '            routeChangeHistory.record(from: fromRoute, to: eventRouteName, reason: reasonName, at: now,\n'
        '                                      fromIsCarAudio: previousIsCarAudio,\n'
        '                                      toIsCarAudio: observedIsCarAudio ?? outs.contains { $0.portType == .carAudio },\n'
        '                                      fromIsBuiltInSpeaker: previousIsBuiltInSpeaker,\n'
        '                                      toIsBuiltInSpeaker: observedIsBuiltInSpeaker ?? outs.contains { $0.portType == .builtInSpeaker },\n'
        '                                      fromIsEQRoute: previousWasOwnDevice, toIsEQRoute: eventIsEQRoute)\n'
        '            routeChangeBurst = routeChangeHistory.isBurst\n'
        '            carAudioSpeakerBounce = routeChangeHistory.isCarAudioSpeakerBounce\n', 1)
    audio_source = audio_source.replace(
        '        if routeChangeBurst != recentRouteChanges { routeChangeBurst = recentRouteChanges }\n',
        '        if routeChangeBurst != recentRouteChanges { routeChangeBurst = recentRouteChanges }\n'
        '        let carAudioBounce = routeChangeHistory.isCarAudioSpeakerBounce\n'
        '        if carAudioSpeakerBounce != carAudioBounce { carAudioSpeakerBounce = carAudioBounce }\n'
        '        let carAudioEQBounce = routeChangeHistory.isCarAudioEQBounce\n'
        '        if self.carAudioEQBounce != carAudioEQBounce { self.carAudioEQBounce = carAudioEQBounce }\n', 1)
audio_source = audio_source.replace(
    '    private var routeChangeHistory = ETRouteChangeHistory()\n',
    '    private var routeChangeHistory = ETRouteChangeHistory(\n'
    '        restoring: UserDefaults.standard.data(forKey: ETRouteChangeHistory.storageKey),\n'
    '        at: ProcessInfo.processInfo.systemUptime)\n')
if '        routeChangeBurst = routeChangeHistory.isBurst\n        carAudioSpeakerBounce = routeChangeHistory.isCarAudioSpeakerBounce\n' not in audio_source:
    audio_source = audio_source.replace(
        '        // 帰還ループの判定は Swift の写し（AudioSessionRules.swift）で見ている。\n',
        '        routeChangeBurst = routeChangeHistory.isBurst\n'
        '        carAudioSpeakerBounce = routeChangeHistory.isCarAudioSpeakerBounce\n'
        '        carAudioEQBounce = routeChangeHistory.isCarAudioEQBounce\n'
        '        lastRouteChange = routeChangeHistory.summary\n'
        '        // 帰還ループの判定は Swift の写し（AudioSessionRules.swift）で見ている。\n', 1)
if 'UserDefaults.standard.set(data, forKey: ETRouteChangeHistory.storageKey)' not in audio_source:
    audio_source = audio_source.replace(
        '                                      toIsBuiltInSpeaker: observedIsBuiltInSpeaker ?? outs.contains { $0.portType == .builtInSpeaker })\n',
        '                                      toIsBuiltInSpeaker: observedIsBuiltInSpeaker ?? outs.contains { $0.portType == .builtInSpeaker })\n'
        '            if let data = routeChangeHistory.encoded {\n'
        '                UserDefaults.standard.set(data, forKey: ETRouteChangeHistory.storageKey)\n'
        '            }\n', 1)
# Record the exact CarPlay ↔ EQ endpoint pair even when the broader speaker
# detector was already generated by an earlier adaptation pass.
audio_source = audio_source.replace(
    '                                      toIsBuiltInSpeaker: observedIsBuiltInSpeaker ?? outs.contains { $0.portType == .builtInSpeaker })',
    '                                      toIsBuiltInSpeaker: observedIsBuiltInSpeaker ?? outs.contains { $0.portType == .builtInSpeaker },\n'
    '                                      fromIsEQRoute: previousWasOwnDevice, toIsEQRoute: eventIsEQRoute)')
audio_source = audio_source.replace(
    '            carAudioSpeakerBounce = routeChangeHistory.isCarAudioSpeakerBounce\n',
    '            carAudioSpeakerBounce = routeChangeHistory.isCarAudioSpeakerBounce\n'
    '            carAudioEQBounce = routeChangeHistory.isCarAudioEQBounce\n')
audio_source = audio_source.replace(
    '        carAudioSpeakerBounce = routeChangeHistory.isCarAudioSpeakerBounce\n',
    '        carAudioSpeakerBounce = routeChangeHistory.isCarAudioSpeakerBounce\n'
    '        carAudioEQBounce = routeChangeHistory.isCarAudioEQBounce\n')
audio_source = audio_source.replace(
    '        if carAudioSpeakerBounce != carAudioBounce { carAudioSpeakerBounce = carAudioBounce }\n',
    '        if carAudioSpeakerBounce != carAudioBounce { carAudioSpeakerBounce = carAudioBounce }\n'
    '        let carAudioEQBounce = routeChangeHistory.isCarAudioEQBounce\n'
    '        if self.carAudioEQBounce != carAudioEQBounce { self.carAudioEQBounce = carAudioEQBounce }\n')
audio_source = re.sub(r'(?m)^\s*carAudioEQBounce = routeChangeHistory\.isCarAudioEQBounce\n', '', audio_source)
audio_source = re.sub(
    r'(?m)^(\s*)carAudioSpeakerBounce = routeChangeHistory\.isCarAudioSpeakerBounce\n',
    lambda match: match.group(0) + match.group(1) + 'carAudioEQBounce = routeChangeHistory.isCarAudioEQBounce\n',
    audio_source)
audio_source = re.sub(
    r'(?m)^\s*let carAudioEQBounce = routeChangeHistory\.isCarAudioEQBounce\n'
    r'\s*if self\.carAudioEQBounce != carAudioEQBounce \{ self\.carAudioEQBounce = carAudioEQBounce \}\n',
    '', audio_source)
audio_source = re.sub(
    r'(?m)^(\s*if carAudioSpeakerBounce != carAudioBounce \{ carAudioSpeakerBounce = carAudioBounce \}\n)',
    lambda match: match.group(1) + match.group(1).split('if')[0] +
        'let carAudioEQBounce = routeChangeHistory.isCarAudioEQBounce\n' +
        match.group(1).split('if')[0] +
        'if self.carAudioEQBounce != carAudioEQBounce { self.carAudioEQBounce = carAudioEQBounce }\n',
    audio_source)
route_history_declaration = (
    '    private var routeChangeHistory = ETRouteChangeHistory(\n'
    '        restoring: UserDefaults.standard.data(forKey: ETRouteChangeHistory.storageKey),\n'
    '        at: ProcessInfo.processInfo.systemUptime)\n')
first_history = audio_source.find(route_history_declaration)
if first_history >= 0:
    prefix = audio_source[:first_history + len(route_history_declaration)]
    suffix = audio_source[first_history + len(route_history_declaration):]
    audio_source = prefix + suffix.replace(route_history_declaration, '')
route_history_comment = '    /// Bounded route evidence, separated from AVAudioSession so its window rules are testable.\n'
first_comment = audio_source.find(route_history_comment)
if first_comment >= 0:
    prefix = audio_source[:first_comment + len(route_history_comment)]
    suffix = audio_source[first_comment + len(route_history_comment):]
    audio_source = prefix + suffix.replace(route_history_comment, '')
audio_source = audio_source.replace(
    route_history_declaration + route_history_comment,
    route_history_comment + route_history_declaration)
route_history_persist = (
    '            if let data = routeChangeHistory.encoded {\n'
    '                UserDefaults.standard.set(data, forKey: ETRouteChangeHistory.storageKey)\n'
    '            }\n')
first_persist = audio_source.find(route_history_persist)
if first_persist >= 0:
    prefix = audio_source[:first_persist + len(route_history_persist)]
    suffix = audio_source[first_persist + len(route_history_persist):]
    audio_source = prefix + suffix.replace(route_history_persist, '')
audio_io.write_text(audio_source)

pipeline_source = pipeline_source.replace(
    '    @State private var routeFallback = false\n'
    '    @State private var lastRouteChange = ""\n'
    '    @State private var routeChangeBurst = false\n'
    '    @State private var carAudioActive = false\n'
    '    @State private var routeReturnedFromSonanceEQ = false\n',
    '    @State private var routeFallback = false\n'
    '    @State private var routeReturnedFromSonanceEQ = false\n'
    '    @State private var carAudioActive = false\n'
    '    @State private var lastRouteChange = ""\n'
    '    @State private var routeChangeBurst = false\n')
pipeline_source = pipeline_source.replace(
    '            routeFallback = io.routeFallback\n'
    '            lastRouteChange = io.lastRouteChange\n'
    '            routeChangeBurst = io.routeChangeBurst\n'
    '            carAudioActive = io.carAudioActive\n'
    '            routeReturnedFromSonanceEQ = io.routeReturnedFromSonanceEQ\n',
    '            routeFallback = io.routeFallback\n'
    '            routeReturnedFromSonanceEQ = io.routeReturnedFromSonanceEQ\n'
    '            carAudioActive = io.carAudioActive\n'
    '            lastRouteChange = io.lastRouteChange\n'
    '            routeChangeBurst = io.routeChangeBurst\n')
pipeline_source = pipeline_source.replace(
    '        .onReceive(io.$routeFallback) { routeFallback = $0 }\n'
    '        .onReceive(io.$lastRouteChange) { lastRouteChange = $0 }\n'
    '        .onReceive(io.$routeChangeBurst) { routeChangeBurst = $0 }\n'
    '        .onReceive(io.$carAudioActive) { carAudioActive = $0 }\n'
    '        .onReceive(io.$routeReturnedFromSonanceEQ) { routeReturnedFromSonanceEQ = $0 }\n',
    '        .onReceive(io.$routeFallback) { routeFallback = $0 }\n'
    '        .onReceive(io.$routeReturnedFromSonanceEQ) { routeReturnedFromSonanceEQ = $0 }\n'
    '        .onReceive(io.$carAudioActive) { carAudioActive = $0 }\n'
    '        .onReceive(io.$lastRouteChange) { lastRouteChange = $0 }\n'
    '        .onReceive(io.$routeChangeBurst) { routeChangeBurst = $0 }\n')
pipeline_source = pipeline_source.replace(
    '    let routeFallback: Bool\n'
    '    let routeChangeBurst: Bool\n'
    '    let lastRouteChange: String\n'
    '    let carAudioActive: Bool\n'
    '    let routeReturnedFromSonanceEQ: Bool\n',
    '    let routeFallback: Bool\n'
    '    let routeReturnedFromSonanceEQ: Bool\n'
    '    let carAudioActive: Bool\n'
    '    let routeChangeBurst: Bool\n'
    '    let lastRouteChange: String\n')
pipeline_source = pipeline_source.replace(
    '        if routeReturnedFromSonanceEQ { return "Audio left the EQ route for \\(currentRoute)" }\n'
    '        if routeChangeBurst { return "Audio route keeps changing" }',
    '        if routeChangeBurst { return "Audio route keeps changing" }\n'
    '        if routeReturnedFromSonanceEQ { return "Audio left the EQ route for \\(currentRoute)" }')
pipeline_source = pipeline_source.replace(
    '        if routeReturnedFromSonanceEQ {\n'
    '            return "iOS moved playback from Sonance EQ to this output; that handoff alone does not mean the EQ is faulty. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, stop retrying that route. Keep CarPlay selected for car audio (EQ is bypassed), or use a compatible player / local file for EQ. Sonance EQ cannot override iOS route selection."\n'
    '        }\n'
    '        if routeChangeBurst {\n'
    '            return "iOS changed the audio route several times in 30 seconds. Recent changes: \\(lastRouteChange). Stop toggling between routes. For car audio, leave CarPlay selected (EQ is bypassed); for EQ, use a compatible player or local file."\n'
    '        }',
    '        if routeChangeBurst {\n'
    '            return "iOS changed the audio route several times in 30 seconds. Recent changes: \\(lastRouteChange). Stop toggling between routes. For car audio, leave CarPlay selected (EQ is bypassed); for EQ, use a compatible player or local file."\n'
    '        }\n'
    '        if routeReturnedFromSonanceEQ {\n'
    '            return "iOS moved playback from Sonance EQ to this output; that handoff alone does not mean the EQ is faulty. If the player says EffectDeck Audio or Sonance EQ Audio is unsupported, stop retrying that route. Keep CarPlay selected for car audio (EQ is bypassed), or use a compatible player / local file for EQ. Sonance EQ cannot override iOS route selection."\n'
    '        }')
banner_start = pipeline_source.find('private struct ConnectBanner')
title_start = pipeline_source.find('    private var title: String {', banner_start)
existing_presentation_start = pipeline_source.find(
    '    private var presentation: ETRouteStatusPresentation {', banner_start)
body_start = pipeline_source.find('    var body: some View {', title_start)
if min(banner_start, title_start, body_start) < 0:
    raise SystemExit(f"Could not find the ConnectBanner presentation block: {pipeline}")
presentation_block = (
    '    private var presentation: ETRouteStatusPresentation {\n'
    '        ETRouteStatusPresentation.make(\n'
    '            restartNeeded: restartNeeded,\n'
    '            deviceName: UIDevice.current.model,\n'
    '            currentRoute: currentRoute,\n'
    '            routeFallback: routeFallback,\n'
    '            routeReturnedFromSonanceEQ: routeReturnedFromSonanceEQ,\n'
    '            carAudioActive: carAudioActive,\n'
    '            routeChangeBurst: routeChangeBurst,\n'
    '            lastRouteChange: lastRouteChange,\n'
    '            carAudioSpeakerBounce: carAudioSpeakerBounce,\n'
    '            carAudioEQBounce: carAudioEQBounce)\n'
    '    }\n\n'
    '    private var title: String { presentation.title }\n'
    '    private var instruction: String { presentation.instruction }\n\n')
presentation_start = existing_presentation_start if existing_presentation_start >= 0 else title_start
pipeline_source = pipeline_source[:presentation_start] + presentation_block + pipeline_source[body_start:]
if '@State private var carAudioSpeakerBounce = false' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        '    @State private var routeChangeBurst = false\n',
        '    @State private var routeChangeBurst = false\n'
        '    @State private var carAudioSpeakerBounce = false\n', 1)
if '@State private var carAudioEQBounce = false' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        '    @State private var carAudioSpeakerBounce = false\n',
        '    @State private var carAudioSpeakerBounce = false\n'
        '    @State private var carAudioEQBounce = false\n', 1)
if '            carAudioSpeakerBounce = io.carAudioSpeakerBounce' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        '            routeChangeBurst = io.routeChangeBurst\n',
        '            routeChangeBurst = io.routeChangeBurst\n'
        '            carAudioSpeakerBounce = io.carAudioSpeakerBounce\n', 1)
if '            carAudioEQBounce = io.carAudioEQBounce' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        '            carAudioSpeakerBounce = io.carAudioSpeakerBounce\n',
        '            carAudioSpeakerBounce = io.carAudioSpeakerBounce\n'
        '            carAudioEQBounce = io.carAudioEQBounce\n', 1)
if '.onReceive(io.$carAudioSpeakerBounce)' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        '        .onReceive(io.$routeChangeBurst) { routeChangeBurst = $0 }\n',
        '        .onReceive(io.$routeChangeBurst) { routeChangeBurst = $0 }\n'
        '        .onReceive(io.$carAudioSpeakerBounce) { carAudioSpeakerBounce = $0 }\n', 1)
if '.onReceive(io.$carAudioEQBounce)' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        '        .onReceive(io.$carAudioSpeakerBounce) { carAudioSpeakerBounce = $0 }\n',
        '        .onReceive(io.$carAudioSpeakerBounce) { carAudioSpeakerBounce = $0 }\n'
        '        .onReceive(io.$carAudioEQBounce) { carAudioEQBounce = $0 }\n', 1)
pipeline_source = pipeline_source.replace(
    '                routeChangeBurst: routeChangeBurst) {\n'
    '                ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, routeFallback: routeFallback, routeReturnedFromSonanceEQ: routeReturnedFromSonanceEQ, carAudioActive: carAudioActive, routeChangeBurst: routeChangeBurst, lastRouteChange: lastRouteChange, openTips: { presentSheet(.tips) })',
    '                routeChangeBurst: routeChangeBurst,\n'
    '                carAudioSpeakerBounce: carAudioSpeakerBounce,\n'
    '                carAudioEQBounce: carAudioEQBounce) {\n'
    '                ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, routeFallback: routeFallback, routeReturnedFromSonanceEQ: routeReturnedFromSonanceEQ, carAudioActive: carAudioActive, routeChangeBurst: routeChangeBurst, carAudioSpeakerBounce: carAudioSpeakerBounce, carAudioEQBounce: carAudioEQBounce, lastRouteChange: lastRouteChange, openTips: { presentSheet(.tips) })')
pipeline_source = pipeline_source.replace(
    '    let routeChangeBurst: Bool\n'
    '    let lastRouteChange: String\n',
    '    let routeChangeBurst: Bool\n'
    '    let carAudioSpeakerBounce: Bool\n'
    '    let carAudioEQBounce: Bool\n'
    '    let lastRouteChange: String\n', 1)
if '    let carAudioEQBounce: Bool' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        '    let carAudioSpeakerBounce: Bool\n',
        '    let carAudioSpeakerBounce: Bool\n'
        '    let carAudioEQBounce: Bool\n', 1)
pipeline_source = pipeline_source.replace(
    '            routeChangeBurst: routeChangeBurst,\n'
    '            lastRouteChange: lastRouteChange)',
    '            routeChangeBurst: routeChangeBurst,\n'
    '            lastRouteChange: lastRouteChange,\n'
    '            carAudioSpeakerBounce: carAudioSpeakerBounce,\n'
    '            carAudioEQBounce: carAudioEQBounce)', 1)
pipeline_source = pipeline_source.replace(
    'routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst)',
    'routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst || carAudioSpeakerBounce || carAudioEQBounce)')
pipeline_source = pipeline_source.replace(
    'routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst) ? AnyShapeStyle(Color.orange)',
    'routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst || carAudioSpeakerBounce || carAudioEQBounce) ? AnyShapeStyle(Color.orange)')
pipeline_source = pipeline_source.replace(
    'routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst) ? Color.orange',
    'routeFallback || routeReturnedFromSonanceEQ || routeChangeBurst || carAudioSpeakerBounce || carAudioEQBounce) ? Color.orange')
pipeline_source = pipeline_source.replace(
    'carAudioSpeakerBounce: carAudioSpeakerBounce)',
    'carAudioSpeakerBounce: carAudioSpeakerBounce, carAudioEQBounce: carAudioEQBounce)')
pipeline_source = pipeline_source.replace(
    'carAudioSpeakerBounce: carAudioSpeakerBounce, lastRouteChange:',
    'carAudioSpeakerBounce: carAudioSpeakerBounce, carAudioEQBounce: carAudioEQBounce, lastRouteChange:')
pipeline_source = pipeline_source.replace(
    '            carAudioSpeakerBounce = io.carAudioSpeakerBounce\n'
    '            carAudioSpeakerBounce = io.carAudioSpeakerBounce\n',
    '            carAudioSpeakerBounce = io.carAudioSpeakerBounce\n')
pipeline_source = pipeline_source.replace(
    '        .onReceive(io.$carAudioSpeakerBounce) { carAudioSpeakerBounce = $0 }\n'
    '        .onReceive(io.$carAudioSpeakerBounce) { carAudioSpeakerBounce = $0 }\n',
    '        .onReceive(io.$carAudioSpeakerBounce) { carAudioSpeakerBounce = $0 }\n')
if 'var openLocalPlayer: () -> Void = {}' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        'struct PipelineView: View {\n',
        'struct PipelineView: View {\n'
        '    /// Switch to the built-in file player when a source cannot use the EQ route.\n'
        '    var openLocalPlayer: () -> Void = {}\n', 1)
pipeline_source = pipeline_source.replace(
    'lastRouteChange: lastRouteChange, openTips: { presentSheet(.tips) })',
    'lastRouteChange: lastRouteChange, openTips: { presentSheet(.tips) }, openLocalPlayer: openLocalPlayer)')
if '    let openLocalPlayer: () -> Void' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        '    let openTips: () -> Void\n',
        '    let openTips: () -> Void\n'
        '    let openLocalPlayer: () -> Void\n', 1)
if '    let noAudioAvailable: Bool' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        '    let restartNeeded: Bool\n',
        '    let restartNeeded: Bool\n'
        '    let noAudioAvailable: Bool\n', 1)
pipeline_source = pipeline_source.replace(
    'ConnectBanner(restartNeeded: restartNeeded, currentRoute:',
    'ConnectBanner(restartNeeded: restartNeeded, noAudioAvailable: !hasPeer, currentRoute:')
pipeline_source = pipeline_source.replace(
    '                    restartNeeded: restartNeeded,\n'
    '                    routeFallback: routeFallback,',
    '                    restartNeeded: restartNeeded,\n'
    '                    noAudioAvailable: noAudioAvailable,\n'
    '                    routeFallback: routeFallback,')
if 'noAudioAvailable: noAudioAvailable,' not in pipeline_source:
    pipeline_source = re.sub(
        r'(ETRouteStatusPresentation\.shouldOfferLocalPlayerRecovery\(\s*'
        r'restartNeeded: restartNeeded,\n)',
        r'\1                        noAudioAvailable: noAudioAvailable,\n',
        pipeline_source,
        count=1)
if 'Button(action: openLocalPlayer)' not in pipeline_source:
    pipeline_source = pipeline_source.replace(
        '                .accessibilityLabel(restartNeeded ? "Restart required, issue 12" : "Known limitations")\n',
        '                .accessibilityLabel(restartNeeded ? "Restart required, issue 12" : "Known limitations")\n'
        '\n'
        '                if ETRouteStatusPresentation.shouldOfferLocalPlayerRecovery(\n'
        '                    restartNeeded: restartNeeded,\n'
            '                    noAudioAvailable: !hasPeer,\n'
        '                    routeFallback: routeFallback,\n'
        '                    routeReturnedFromSonanceEQ: routeReturnedFromSonanceEQ,\n'
        '                    carAudioActive: carAudioActive,\n'
        '                    routeChangeBurst: routeChangeBurst,\n'
        '                    carAudioSpeakerBounce: carAudioSpeakerBounce,\n'
        '                    carAudioEQBounce: carAudioEQBounce) {\n'
        '                    Button(action: openLocalPlayer) {\n'
        '                        Label("Open Player", systemImage: "music.note")\n'
        '                            .etFont(size: 13, weight: .semibold)\n'
        '                            .padding(.horizontal, 6)\n'
        '                            .padding(.vertical, 7)\n'
        '                    }\n'
        '                    .buttonStyle(.borderedProminent)\n'
        '                    .accessibilityLabel("Open Sonance EQ local audio player")\n'
        '                }\n', 1)
pipeline.write_text(pipeline_source)
