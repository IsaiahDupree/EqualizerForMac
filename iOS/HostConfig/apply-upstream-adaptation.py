#!/usr/bin/env python3
"""Apply the small Sonance identity bridge to the pinned EffectDeck source tree."""
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "Vendor" / "EffectDeck"
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
        'return "Pick EffectDeck as the output in Control Center."':
        'return "No audio is reaching Sonance EQ. If the player says it does not support Sonance EQ Audio, it cannot send audio to this route. Choose CarPlay directly or play a local file in Sonance EQ. If audio switches back without that message, tap Help."',
        'return "Pick Sonance EQ as the output in Control Center."':
        'return "No audio is reaching Sonance EQ. If the player says it does not support Sonance EQ Audio, it cannot send audio to this route. Choose CarPlay directly or play a local file in Sonance EQ. If audio switches back without that message, tap Help."',
    },
    root / "Sources/EffeTuneLive/Views/PipelineView.swift": {},
    root / "Sources/Extension/EffeTuneLiveExtension.swift": {
        'let kProtocolID = "media-device-protocol.ai.nemut.effetune"':
        'let kProtocolID = "media-device-protocol.com.isaiahdupree.SonanceEQ.iOSPrototype"',
    },
    root / "Sources/EffeTuneLive/DSP/ETShareInbox.swift": {
        'static let group = "group.ai.nemut.effetune"':
        'static let group = "group.com.isaiahdupree.SonanceEQ"',
    },
    root / "Sources/ShareExtension/ShareViewController.swift": {
        '.navigationTitle("EffectDeck")': '.navigationTitle("Sonance EQ")',
    },
    root / "Sources/EffeTuneLive/Views/ConnectionTipsView.swift": {
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
            '              en: .init(title: "A player says it does not support Sonance EQ Audio",\n'
            '                        act: "Choose CarPlay directly to restore car audio, or play a local file in Sonance EQ. For streaming audio, use a player that supports the Sonance EQ route.",\n'
            '                        why: "The player must opt in to Apple\'s AVSystemRouting API before iOS can send its audio to this route. Sonance EQ cannot make an unsupported player stream, so iOS may return playback to iPhone or CarPlay."),\n'
            '              ja: .init(title: "プレイヤーに「Sonance EQ Audioはサポートされていません」と表示される",\n'
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
    for expected in replacements.values():
        if expected not in source:
            raise SystemExit(f"Expected upstream adaptation missing: {path}: {expected}")
    path.write_text(source)

# These are structural insertions: their old text remains a substring of the
# inserted text, so keep them separate from global replacements and guard each
# with a unique new-source marker to make repeated project generation safe.
pipeline = root / "Sources/EffeTuneLive/Views/PipelineView.swift"
source = pipeline.read_text()
insertions = {
    '    @State private var restartNeeded = false\n':
    '    @State private var restartNeeded = false\n    @State private var outputRoute = "—"\n    @State private var routeFallback = false\n',
    '            restartNeeded = io.restartNeeded\n':
    '            restartNeeded = io.restartNeeded\n            outputRoute = io.outputRoute\n            routeFallback = io.routeFallback\n',
    '        .onReceive(io.$restartNeeded) { restartNeeded = $0 }\n':
    '        .onReceive(io.$restartNeeded) { restartNeeded = $0 }\n'
    '        .onReceive(io.$outputRoute) { outputRoute = $0 }\n'
    '        .onReceive(io.$routeFallback) { routeFallback = $0 }\n',
    '                    Text(instruction)\n                        .etFont(size: 12)\n                        .foregroundStyle(.secondary)\n                        .fixedSize(horizontal: false, vertical: true)':
    '                    Text(instruction)\n                        .etFont(size: 12)\n                        .foregroundStyle(.secondary)\n                        .fixedSize(horizontal: false, vertical: true)\n                    if !currentRoute.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, currentRoute != "—" {\n                        Text("Current output seen by Sonance EQ: \\(currentRoute)")\n                            .etFont(size: 11)\n                            .foregroundStyle(.secondary)\n                            .fixedSize(horizontal: false, vertical: true)\n                    }',
}
route_wiring = {
    'ConnectBanner(restartNeeded: restartNeeded, openTips: { presentSheet(.tips) })':
    'ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, routeFallback: routeFallback, openTips: { presentSheet(.tips) })',
    'ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, openTips: { presentSheet(.tips) })':
    'ConnectBanner(restartNeeded: restartNeeded, currentRoute: outputRoute, routeFallback: routeFallback, openTips: { presentSheet(.tips) })',
    '    let restartNeeded: Bool\n    let openTips: () -> Void':
    '    let restartNeeded: Bool\n    let currentRoute: String\n    let routeFallback: Bool\n    let openTips: () -> Void',
    '    let restartNeeded: Bool\n    let currentRoute: String\n    let openTips: () -> Void':
    '    let restartNeeded: Bool\n    let currentRoute: String\n    let routeFallback: Bool\n    let openTips: () -> Void',
}
for old, new in route_wiring.items():
    if new not in source and old in source:
        source = source.replace(old, new, 1)
for new in set(route_wiring.values()):
    if new not in source:
        raise SystemExit(f"Expected route wiring missing: {pipeline}: {new}")

for old, new in insertions.items():
    if new not in source and old in source:
        source = source.replace(old, new, 1)
    if new not in source:
        raise SystemExit(f"Expected route status adaptation missing: {pipeline}: {new}")

# Make an observed return to the built-in speaker or car audio explicit. The
# route picker itself remains owned by iOS Control Center; this is diagnosis,
# not a private or silent route-selection attempt.
if 'return routeFallback ? "Audio route fallback detected"' not in source:
    source = source.replace(
        '        restartNeeded ? "\\(UIDevice.current.model) Restart Required" : "No audio yet"',
        '        if restartNeeded { return "\\(UIDevice.current.model) Restart Required" }\n'
        '        return routeFallback ? "Audio route fallback detected" : "No audio yet"', 1)
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
        '            return "Sonance EQ detected audio routed to \\(currentRoute). Open Control Center, select Sonance EQ, then resume playback. If the player says this route is unsupported, use CarPlay directly or a compatible player."\n'
        '        }\n'
        '        return "Pick Sonance EQ in Control Center. If the player says this route is unsupported, use CarPlay directly or a compatible player."')
    for old_instruction in old_instructions:
        if old_instruction in source:
            source = source.replace(old_instruction, new_instruction, 1)
            break
    if 'if routeFallback {' not in source:
        raise SystemExit(f"Could not install route fallback diagnosis in {pipeline}")
pipeline.write_text(source)

audio_io = root / "Sources/EffeTuneLive/Audio/AudioIO.swift"
source = audio_io.read_text()
if "@Published var routeFallback = false" not in source:
    source = source.replace(
        '    @Published var outputRoute: String = "—"\n',
        '    @Published var outputRoute: String = "—"\n'
        '    /// iOS returned playback to the built-in speaker or car-audio route while no source link is active.\n'
        '    @Published var routeFallback = false\n', 1)
if "let nowRouteIsFallback" not in source:
    source = source.replace(
        '        let nowRoute = outs.isEmpty ? "no output" : names\n',
        '        let nowRoute = outs.isEmpty ? "no output" : names\n'
        '        let nowRouteIsFallback = outs.contains {\n'
        '            $0.portType == .builtInSpeaker || $0.portType == .carAudio\n'
        '        }\n'
        '        if routeFallback != nowRouteIsFallback { routeFallback = nowRouteIsFallback }\n', 1)
if "@Published var routeFallback = false" not in source or "let nowRouteIsFallback" not in source:
    raise SystemExit(f"Expected route fallback observer missing: {audio_io}")
audio_io.write_text(source)
