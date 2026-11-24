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
        'return "Pick Sonance EQ as the output in Control Center. Install Sonance EQ Route if it is not listed."',
        'return "Pick Sonance EQ as the output in Control Center."':
        'return "Pick Sonance EQ as the output in Control Center. Install Sonance EQ Route if it is not listed."',
    },
    root / "Sources/EffeTuneLive/Views/PipelineView.swift": {
        'restartNeeded\n            ? "Restart once after this update, then pick EffectDeck in Control Center."\n            : "Pick EffectDeck as the output in Control Center."':
        'restartNeeded\n            ? "Restart once after this update, then pick Sonance EQ in Control Center. Install Sonance EQ Route if it is not listed."\n            : "Pick Sonance EQ as the output in Control Center. Install Sonance EQ Route if it is not listed."',
        'restartNeeded\n            ? "Restart once after this update, then pick Sonance EQ in Control Center."\n            : "Pick Sonance EQ as the output in Control Center."':
        'restartNeeded\n            ? "Restart once after this update, then pick Sonance EQ in Control Center. Install Sonance EQ Route if it is not listed."\n            : "Pick Sonance EQ as the output in Control Center. Install Sonance EQ Route if it is not listed."',
    },
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
