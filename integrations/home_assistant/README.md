# Sonance Home for Home Assistant

Sonance Home carries the real Sonance EQ curves into Music Assistant's DSP pipeline, then gives
Home Assistant one action for **preset + destination + playback**. It supports Google Nest,
Chromecast Audio, Chromecast built-in speakers, Cast groups, and every other Music Assistant player.

## What ships

- `custom_components/sonance_eq`: authenticated local integration for Music Assistant DSP.
- `www/sonance-home-card.js`: a compact Lovelace card with player, media, and EQ selectors.
- `install.sh`: copies both into an existing Home Assistant configuration directory.
- Nine presets: Flat, Bass Boost, Treble, Vocal, Loudness, Warm Room, Night, Small Speaker, Cinema.
- Three Home Assistant actions: `sync_presets`, `apply_preset`, and `send_to_device`.

Boosting presets include compensating preamp headroom and a -2 dB safety limiter. Flat disables DSP
instead of needlessly transcoding a bit-perfect stream.

## Requirements

- Home Assistant with the official Music Assistant integration.
- Music Assistant **2.10.1 or newer**. This is the first stable line verified with the preset-apply
  command and safety-limiter schema used here. It is also newer than the release that fixed the
  [published authenticated API security issue](https://github.com/music-assistant/server/security/advisories/GHSA-cjp7-8r57-vc8f).
- A Music Assistant access token permitted to read and write player DSP configuration.
- Cast/Nest devices and Music Assistant on the same local network with multicast discovery working.

The token stays in Home Assistant's config-entry storage. It is sent only to the configured local
Music Assistant URL as an `Authorization: Bearer` header and is never placed in a media URL or log.

## Install

From this repository:

```bash
./integrations/home_assistant/install.sh /path/to/home-assistant-config
```

Then:

1. Restart Home Assistant.
2. Open **Settings → Devices & services → Add integration → Sonance EQ**.
3. Enter the local Music Assistant URL (normally `http://homeassistant.local:8095`) and access token.
4. In **Settings → Dashboards → Resources**, add `/local/sonance-home-card.js` as a JavaScript module.
5. Add a manual card:

```yaml
type: custom:sonance-home-card
title: Sonance Home
preset: Flat
```

The card discovers current `media_player` entities. Music Assistant players receive both Sonance DSP
and playback. Plain Google Cast entities remain valid playback destinations, but the card disables EQ
for them because direct Cast audio does not pass through Music Assistant.

## Automations

Apply an EQ without changing playback:

```yaml
action: sonance_eq.apply_preset
data:
  entity_id: media_player.living_room
  preset: Vocal
```

Apply an EQ and start a provider URL, HTTP stream, or `media-source://` URI:

```yaml
action: sonance_eq.send_to_device
data:
  entity_id: media_player.kitchen_speaker
  media_id: https://example.net/radio.mp3
  media_type: music
  preset: Warm Room
```

Create or refresh all Sonance presets in Music Assistant:

```yaml
action: sonance_eq.sync_presets
```

## Honest limitations

- A Spotify/YouTube Music app casting directly to a speaker bypasses Music Assistant and therefore
  bypasses Sonance DSP. Start playback through the Sonance card, Home Assistant, or Music Assistant.
- Native Google Cast groups can disable individual player DSP. For per-room corrections, use a
  supported Music Assistant Universal/Sendspin grouping path; otherwise apply one group-safe curve.
- Google Home's own bass/treble setting remains separate and stacks with Sonance DSP. Leave it flat
  when using Sonance presets unless the hardware needs a permanent correction.

## Test

The client suite uses a real local `aiohttp` server and exercises authenticated JSON requests, preset
upserts, application, and the minimum secure Music Assistant version:

```bash
python3 -m pytest integrations/home_assistant/tests -q
```
