# Sonance Home for Home Assistant

Sonance Home makes the real Sonance EQ curves available through three independent local paths:

1. **Home Assistant routing** for every `media_player` that accepts `play_media`.
2. **Music Assistant DSP** for Cast, AirPlay, Sonos, Squeezelite, DLNA, Snapcast, and its other players.
3. **Native Sonance PowerZone output EQ** through the official amplifier control API.

The ecosystem research and product-by-product capability matrix live in
[`COMPATIBILITY-MATRIX.md`](COMPATIBILITY-MATRIX.md).

## What ships

- `custom_components/sonance_eq`: local Home Assistant, Music Assistant, and PowerZone integration.
- `www/sonance-home-card.js`: a compact Lovelace card with player, media, and EQ selectors.
- `install.sh`: copies both into an existing Home Assistant configuration directory.
- Nine presets: Flat, Bass Boost, Treble, Vocal, Loudness, Warm Room, Night, Small Speaker, Cinema.
- Four Home Assistant actions: `sync_presets`, `apply_preset`, `apply_powerzone_preset`, and
  `send_to_device`.
- One standard Home Assistant `select` entity per physical PowerZone output, using the installer-defined
  output name. These are the portable control surface for dashboards, voice bridges, scenes, and other hubs.

Boosting presets include compensating preamp headroom and a -2 dB safety limiter. Flat disables DSP
instead of needlessly transcoding a bit-perfect stream.

## Requirements

Home Assistant routing-only mode has no optional dependency. Add one or both DSP backends when needed:

- **Music Assistant:** version **2.10.1 or newer** and an access token permitted to read/write player
  DSP. This is newer than the release that fixed the
  [published authenticated API security issue](https://github.com/music-assistant/server/security/advisories/GHSA-cjp7-8r57-vc8f).
- **Sonance PowerZone:** a PowerZone Connect/Connect PRO amplifier exposing the official API on the
  private LAN (normally TCP 7621), with output EQ support. Compatible amplifiers are discovered through
  their official `_pasconnect._tcp` mDNS service; manual host entry remains available.

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
3. Choose Home Assistant routing, Music Assistant DSP, or Sonance PowerZone hardware. Add the
   integration again to configure another backend or amplifier.
4. In **Settings → Dashboards → Resources**, add `/local/sonance-home-card.js` as a JavaScript module.
5. Add a manual card:

```yaml
type: custom:sonance-home-card
title: Sonance Home
preset: Flat
```

The card discovers current `media_player` entities. Music Assistant players receive both Sonance DSP
and playback. Any other player remains a valid playback destination. Direct hardware EQ is controlled
from either the generated output selectors or the `apply_powerzone_preset` action and remains active for
every physical source through that amp.

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

Apply a curve directly to physical output 2 of the configured PowerZone amplifier:

```yaml
action: sonance_eq.apply_powerzone_preset
data:
  output_id: 2
  preset: Vocal
```

The same operation through the standard entity API is easier to expose to other home platforms:

```yaml
action: select.select_option
target:
  entity_id: select.living_room_eq_preset
data:
  option: Vocal
```

PowerZone selectors read the real amplifier EQ once when loaded. If an installer programmed a curve that
does not match a managed Sonance preset, the state stays unknown instead of being mislabeled. Presets
applied through either a selector or `apply_powerzone_preset` immediately synchronize the entity state.

## Voice assistants and other hubs

- Expose the output `select` entities directly to Google Assistant or HomeKit Bridge where supported.
- For Alexa or a bridge that does not present enumerated selects well, create a Home Assistant script for
  each voice phrase and call `select.select_option`; expose those scripts/scenes instead.
- Homey Pro can use the native [`com.isaiahdupree.sonanceeq`](../homey/com.isaiahdupree.sonanceeq/README.md)
  app for direct mDNS discovery, one preset picker per physical output, and an Advanced Flow action.
- SmartThings hubs can use the native local [Edge driver](../smartthings/sonance-powerzone/README.md) for
  per-output preset actions and Automations without a cloud relay.
- openHAB, Hubitat, ioBroker, Node-RED, and other broker clients can use the local
  [MQTT bridge](../mqtt/sonance-powerzone-mqtt/README.md) without putting Home Assistant in the path.
  Installations already using HA as their control plane can instead call the standard entity action
  through Home Assistant's authenticated REST/WebSocket interfaces.
- Dealer systems should continue using Sonance's official native driver when it already owns PowerZone
  configuration. Avoid simultaneous writes from two automation controllers.

PowerZone models report their output and user-EQ band counts at runtime. Ten-band models receive the
original curve. Models with fewer bands receive a log-spaced adaptation. Direct-hardware gains are
normalized so the loudest band is 0 dB; this preserves amplifier headroom without overwriting a
calibrated output gain or speaker-protection preset. Only the user output-EQ stage is changed.

## Honest limitations

- A Spotify/YouTube Music app casting directly to a speaker bypasses Music Assistant and therefore
  bypasses Sonance DSP. Start playback through the Sonance card, Home Assistant, or Music Assistant.
- Native Google Cast groups can disable individual player DSP. For per-room corrections, use a
  supported Music Assistant Universal/Sendspin grouping path; otherwise apply one group-safe curve.
- Google Home's own bass/treble setting remains separate and stacks with Sonance DSP. Leave it flat
  when using Sonance presets unless the hardware needs a permanent correction.
- Matter and Thread are device-control layers, not universal audio transports or EQ schemas. Use a
  Home Assistant script/scene for voice and automation exposure.
- The official PowerZone line protocol is unauthenticated. Sonance Home rejects public IP targets;
  keep the amplifier on a trusted/isolated private LAN, block TCP 7621 and port 80 at the WAN edge,
  and never port-forward them.

## Test

The client suite uses real local HTTP and TCP test servers. It exercises authenticated Music Assistant
requests, preset upserts, the minimum secure server version, current `SYSTEM.DEVICE.*` PowerZone identity
registers, protocol parsing, public-target rejection, output discovery, preset-state recognition, safe band
adaptation, listener synchronization, and direct hardware writes:

```bash
python3 -m pytest integrations/home_assistant/tests -q
```

When a physical amplifier is available, run the read-only acceptance probe before enabling writes. It
uses the same private-address and protocol validation as Home Assistant and reports device identity,
output names, and whether each existing user-EQ curve matches a managed Sonance preset:

```bash
python3 integrations/home_assistant/scripts/powerzone_probe.py powerzone.local
```

The probe never changes amplifier state and records `writes_performed: false` in both success and failure
reports.

For a physical Sendspin player, create an isolated environment for the current reference client and run
the read-only inspection first:

```bash
python3 -m venv /tmp/sonance-sendspin-probe
/tmp/sonance-sendspin-probe/bin/pip install \
  -r integrations/home_assistant/scripts/requirements-sendspin-probe.txt
/tmp/sonance-sendspin-probe/bin/python \
  integrations/home_assistant/scripts/sendspin_probe.py 192.168.1.109
```

Three opt-in checks exercise real hardware and restore state before disconnecting:

```bash
/tmp/sonance-sendspin-probe/bin/python \
  integrations/home_assistant/scripts/sendspin_probe.py 192.168.1.109 \
  --control-test --silent-stream-test
```

The control check moves volume by one point and restores it. The stream check sends one second of
digital silence as 48 kHz, 16-bit stereo PCM, verifies the player enters playback, ends the stream, and
verifies it returns to stopped. This validates the transport only; applying a Sonance curve still
requires Music Assistant DSP, downstream PowerZone DSP, or a Sonance EQ audio source that processes the
PCM before handing it to Sendspin.

The guarded EQ check supplies that last source-side path for hardware acceptance. It generates a quiet,
click-free calibration multitone, applies the same ten-band curve and compensating preamp used by the
integration, enforces the -2 dBFS ceiling, temporarily lowers the player volume, and restores the original
volume after the stream ends:

```bash
/tmp/sonance-sendspin-probe/bin/python \
  integrations/home_assistant/scripts/sendspin_probe.py 192.168.1.109 \
  --eq-stream-test Vocal --eq-test-volume 10
```

The JSON receipt includes distinct source/processed SHA-256 hashes, digital level measurements, the
calculated response at all ten band centers, commit latency, scheduling lead, playback/stop acknowledgements,
and volume restoration. This proves the digital curve was rendered into the PCM delivered to the physical
player. It does not replace an acoustic sweep and calibrated measurement microphone for proving the sound
pressure response of the speaker and room.
