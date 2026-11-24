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
        'return "Pick Sonance EQ as the output in Control Center."',
    },
    root / "Sources/EffeTuneLive/Views/PipelineView.swift": {
        'restartNeeded\n            ? "Restart once after this update, then pick EffectDeck in Control Center."\n            : "Pick EffectDeck as the output in Control Center."':
        'restartNeeded\n            ? "Restart once after this update, then pick Sonance EQ in Control Center."\n            : "Pick Sonance EQ as the output in Control Center."',
    },
    root / "Sources/Extension/EffeTuneLiveExtension.swift": {
        'let kProtocolID = "media-device-protocol.ai.nemut.effetune"':
        'let kProtocolID = "media-device-protocol.com.isaiahdupree.SonanceEQ.iOSPrototype"',
    },
    root / "Sources/EffeTuneLive/DSP/ETShareInbox.swift": {
        'static let group = "group.ai.nemut.effetune"':
        'static let group = "group.com.isaiahdupree.SonanceEQ"',
    },
}
for path, replacements in changes.items():
    source = path.read_text()
    for old, new in replacements.items():
        if new in source:
            continue
        if old not in source:
            raise SystemExit(f"Expected upstream anchor missing: {path}: {old}")
        source = source.replace(old, new, 1)
    path.write_text(source)
