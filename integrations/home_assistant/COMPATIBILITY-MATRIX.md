# Sonance Home ecosystem compatibility

Research date: 2026-09-20. This document uses vendor and project documentation rather than assuming
that a logo or generic smart-home protocol implies audio or DSP support.

“Works with all home products” has to be defined by capability. No current standard makes arbitrary
audio hardware expose the same streaming, grouping, and parametric-EQ controls. Sonance Home therefore
uses a layered contract:

- **Route:** any Home Assistant `media_player` that implements `play_media` can be a destination.
- **Stream DSP:** Music Assistant players receive the complete Sonance curve when playback travels
  through Music Assistant.
- **Hardware DSP:** Sonance PowerZone output EQ applies downstream of every source, including direct
  Cast, AirPlay, Spotify Connect, HDMI/TV, analog, and Dante paths wired through that amplifier.
- **Control bridge:** other hubs call a Home Assistant script/action over their supported local or
  cloud bridge. This exposes preset selection and playback but does not invent DSP inside a speaker.

## Control ecosystems

| Ecosystem | Integration path | Capability | Product decision |
|---|---|---|---|
| Home Assistant | Native custom integration, `sonance_eq.*` actions, and one standard preset `select` per PowerZone output | Route + MA DSP + PowerZone DSP | Primary control plane. Routing-only mode no longer requires Music Assistant. |
| Google Home / Assistant | Expose generated HA PowerZone selects, scripts, scenes, or media players; use Google Cast/MA for audio | Voice/control; full DSP only in MA or downstream PowerZone | Supported. Google Home speaker bass/treble remains separate from Sonance EQ. |
| Apple Home / Siri | HA HomeKit Bridge exposes scripts/scenes as switches and generated PowerZone selects as option controls; AirPlay through MA | Voice/control; stream DSP through MA; hardware DSP downstream | Supported through HA bridge. AirPlay itself does not standardize PEQ. |
| Amazon Alexa / Echo | Expose HA scripts/scenes; commercial speaker makers may use Alexa Music/Connected Speaker APIs | Voice/control; Echo playback is not an open generic DSP endpoint | Control supported. Native speaker/product integration is partner/certification work, not a LAN API promise. |
| Samsung SmartThings | Cloud, LAN, Matter, Zigbee, or Z-Wave device integration; call HA REST/script bridge | Control bridge | Supported architecture; a dedicated SmartThings capability/Edge driver is a packaging project. |
| Homey | Homey app custom capabilities + Flow cards or HA bridge | Control bridge | Supported architecture; dedicated app can model preset as an enum and Apply/Send as Flow actions. |
| openHAB | Binding/Thing/Channel, REST action, or MQTT bridge | Control bridge | Supported without changing DSP core. |
| Node-RED | HA nodes, authenticated REST calls, or MQTT | Automation bridge | Supported now through HA actions. |
| Hubitat / ioBroker | Authenticated HA REST or MQTT bridge | Control bridge | Protocol-compatible path; not claimed as a certified native app yet. |
| Control4, Crestron, Savant, RTI, URC, AMX, ELAN, QSC, Symetrix | Sonance-published PowerZone drivers; Sonance Home may coexist on the same LAN | Native amplifier control | Official Sonance driver path is preferred in dealer projects; avoid competing writes to the same output EQ. |
| NICE and other Linkplay/WiiM installer systems | Vendor driver or HA/WiiM local API, then downstream PowerZone where present | Route/control; device-native EQ varies | Supported as a player/control family, not as a universal PEQ contract. |

Evidence:

- [Home Assistant Google Assistant integration](https://www.home-assistant.io/integrations/google_assistant/)
  lists scripts, scenes, selects, and media players as exposable domains.
- [Home Assistant HomeKit Bridge](https://www.home-assistant.io/integrations/homekit/) exposes
  scripts/scenes as switches and selects as option controls.
- [SmartThings device integration types](https://developer.smartthings.com/docs/devices/device-basics)
  include Matter, Thread, Wi-Fi/Ethernet, Zigbee, Z-Wave, LAN, cloud, direct, and mobile devices.
- [Homey device capabilities](https://apps.developer.homey.app/the-basics/devices/capabilities)
  support system/custom capabilities, media UI, and Flow integration.
- [openHAB bindings](https://www.openhab.org/docs/developer/bindings/) expose Things, Channels, bidirectional
  handlers, rule actions, REST availability, and mDNS discovery; its
  [REST API](https://www.openhab.org/docs/configuration/restdocs) can invoke actions.
- [Node-RED concepts](https://nodered.org/docs/user-guide/concepts) include HTTP/event inputs and shared
  MQTT broker connections.
- [Sonance support](https://sonance.com/pages/support) publishes an installer API plus drivers for AMX,
  Control4, Crestron, ELAN, QSC, RTI, Savant, Symetrix, and URC.

## Standards and transports

| Standard/transport | Discovery/control | Carries audio | Standard PEQ | Sonance Home treatment |
|---|---:|---:|---:|---|
| Matter over Wi-Fi/Ethernet/Thread | Yes | No general whole-home audio transport | No | Use for triggers/devices around the audio system, not the audio path. |
| Thread | IP mesh transport | No by itself | No | Border-router/network layer only. A Thread logo does not guarantee Matter. |
| Zigbee / Z-Wave | Device control | No general high-quality audio | No | Buttons, remotes, occupancy, scenes, and automation triggers through the hub. |
| MQTT | Pub/sub control and state | Technically possible but not the intended media transport | Custom topics only | Future optional bridge; HA REST/actions already provide a stable command surface. |
| REST / WebSocket | Control and state | Can reference streams | API-specific | HA API, Music Assistant JSON API, and PowerZone line/WebSocket API are current bridges. |
| mDNS / SSDP / UPnP | Discovery/control | Protocol-dependent | No universal PEQ | PowerZone uses `_pasconnect._tcp`; Cast/AirPlay/MA/DLNA use their own discovery. |
| Google Cast | Yes | Yes | No portable PEQ | Route through Music Assistant for stream DSP or through PowerZone for hardware DSP. |
| AirPlay / AirPlay 2 | Yes | Yes | No portable PEQ | Route through Music Assistant or use downstream PowerZone. |
| Sonos | Proprietary/UPnP control | Yes | Device-specific tone controls | Prefer MA's native Sonos provider for Sonance stream DSP. |
| DLNA/UPnP DMR | SSDP/UPnP | Yes | Optional/vendor-specific sound modes | Route works; MA warns that vendor implementations vary. |
| HEOS | Local HEOS protocol | Yes | Device-specific | HA provides playback/group control; MA or downstream PowerZone supplies consistent Sonance curve. |
| Yamaha MusicCast | Local MusicCast API | Yes | Native bass/mid/treble on supported devices | HA can control native 3-band EQ; do not claim it is equivalent to the Sonance 10-band curve. |
| Squeezelite/Slimproto, Snapcast, Sendspin | Local player protocols | Yes | DSP depends on server/player | Strong targets for MA stream DSP and synchronized rooms. |
| Spotify/TIDAL Connect | Service-to-device session | Yes | No generic external PEQ contract | Direct Connect bypasses MA DSP; PowerZone downstream EQ still applies. |
| Bluetooth | Pairing/profile-specific | Yes | No cross-vendor PEQ | Treat as a hardware source; apply EQ downstream in PowerZone when available. |
| HDMI/eARC, optical, analog | Physical source | Yes | No control-plane PEQ | PowerZone is the correct universal EQ point when the signal passes through it. |
| Dante AoIP | Network audio | Yes | Control is product-specific | Supported by selected PowerZone models; use amplifier DSP/API for the curve. |

Matter is deliberately not used as the Sonance transport. Home Assistant documents that Matter is a
control protocol over IP/Thread and that Home Assistant is a controller, not a bridge that turns existing
HA entities into Matter devices. It also recommends native integrations when they expose richer vendor
features. See [Home Assistant Matter](https://www.home-assistant.io/integrations/matter/) and
[Google's supported Matter device types](https://developers.home.google.com/matter/supported-devices).

## Audio product families

| Family | Send/play | Full Sonance curve | Notes |
|---|---:|---:|---|
| Google Nest, Google Home, Chromecast Audio, Chromecast built-in, Cast groups | Yes | Yes through MA; yes downstream through PowerZone | Direct app casting bypasses MA. Native Google bass/treble may stack. |
| Sonos / IKEA Symfonisk | Yes | Yes through MA; yes downstream where physically connected | Prefer native Sonos provider, not generic DLNA. |
| Apple TV, HomePod, AirPlay speakers/receivers | Yes where AirPlay/HA player supports it | Yes through MA; yes downstream | Apple provides AirPlay media APIs, not a universal external PEQ API. |
| WiiM / Linkplay | Yes through HA, Cast, AirPlay, DLNA, Squeezelite, Connect protocols | Yes through MA-compatible transport or PowerZone | WiiM publishes HTTP/UPnP APIs and installer integrations; public PEQ depth varies by model/API. |
| Denon/Marantz HEOS and AVRs | Yes | Yes through MA flow/native player path or PowerZone | HA supports playback, groups, favorites, queues; AVR-native DSP is separate. |
| Yamaha MusicCast | Yes | MA/PowerZone; native HA only offers supported device EQ controls | HA exposes high/mid/low and bass/treble on compatible models. |
| Bluesound/BluOS, Bose SoundTouch, Bang & Olufsen, Cambridge Audio | Yes through their HA/MA/native paths | MA when supported or downstream PowerZone | Capability must be detected per device; brand presence alone is not PEQ support. |
| DLNA TVs, radios, streamers | Usually | MA if device streams reliably; PowerZone downstream | DLNA implementations and accepted codecs vary significantly. |
| Raspberry Pi / Linux endpoints with Squeezelite, Snapcast, Sendspin, MPD | Yes | Yes | Best open/local path for custom rooms and DIY endpoints. |
| ESPHome/ESP32 audio endpoints | Device/project dependent | Via supported MA player protocol or downstream DSP | Zigbee/Thread/BLE discovery alone does not make an audio sink. |
| Sonance PowerZone Connect / Connect PRO | Source independent | Native hardware path | Official API exposes per-output user EQ, band count, gain/frequency/Q/type, bypass, limiters, routing, and metering. |
| Sonance DSP MKIII / UA series | Product-specific IP/IR or local app | Hardware supports DSP; public automation surface differs | Do not assume the PowerZone API applies to every Sonance amp family. Add a tested adapter per published protocol. |

Representative official references:

- [Music Assistant player support](https://www.music-assistant.io/player-support/) and
  [technical behavior](https://www.music-assistant.io/faq/tech-info/) cover Cast, Sonos, AirPlay,
  Squeezelite, DLNA, Snapcast, HA-imported players, native enqueue, and flow mode.
- [Music Assistant DSP](https://www.music-assistant.io/dsp/) is the stream-path DSP authority.
- [Home Assistant Cast](https://www.home-assistant.io/integrations/cast/),
  [Sonos](https://www.home-assistant.io/integrations/sonos),
  [DLNA DMR](https://www.home-assistant.io/integrations/dlna_dmr),
  [HEOS](https://www.home-assistant.io/integrations/heos/), and
  [MusicCast](https://www.home-assistant.io/integrations/yamaha_musiccast/) document the player-specific
  routing and control surfaces.
- [WiiM support](https://www.wiimhome.com/support) documents HTTP/UPnP APIs, Cast, AirPlay 2, Connect
  protocols, Alexa/Google/Siri, groups, and installer integrations.
- [Apple accessories](https://developer.apple.com/accessories/) documents AirPlay 2 media APIs and
  HomeKit accessory requirements.
- [Alexa Music Skill API](https://developer.amazon.com/en-US/docs/alexa/music-skills/understand-the-music-skill-api.html)
  and [Connected Speaker/AVR integration](https://developer.amazon.com/en-US/alexa/devices/speakers/cloud-controlled-soundbars-avrs)
  show that native Alexa speaker integration is a commercial skill/device program.

## Native PowerZone contract

The direct adapter follows Sonance's
[Open API for Installers, edition 2026.24.1](https://images.salsify.com/images/vvbm6qkvqkj23mr6x4nq/Open%20API%20for%20Installers_Sonance_2026.24.1.pdf):

- Discover `_pasconnect._tcp` over mDNS, then use raw TCP 7621 or `ws://<amp>/ws`.
- Read `API_VERSION`, `OUT.COUNT`, and `OUT.EQ.COUNT` before applying anything.
- Modify only `OUT-{n}.EQ-*`, the documented user-adjustable output EQ. Do not modify protected
  speaker EQ, FIR, crossover, or limiter calibration.
- Keep the whole output EQ bypassed while changing bands; enable it only after every write succeeds.
- Normalize positive boosts to 0 dB instead of overwriting calibrated output gain or protection data.
- `Flat` bypasses user EQ.
- The protocol is unauthenticated. The integration rejects public resolved addresses. Network ACLs,
  VLAN/firewall policy, and no port-forwarding are mandatory because host validation is defense in depth,
  not device authentication.

## Product acceptance test

A new product is “integrated” only after recording all six answers:

1. How is it discovered, and does discovery cross the actual home network topology?
2. Can Home Assistant call play/pause/volume/source and `play_media` on it?
3. Which audio transport reaches it, and which codecs/URLs does it accept?
4. Where does DSP run: Music Assistant, native device API, PowerZone downstream, or nowhere?
5. Do groups preserve individual DSP, share one group curve, or bypass the processing path?
6. Is control local and authenticated? If not, what firewall/VLAN boundary contains it?

This prevents a common false positive: “the device appears in the hub” proves discovery/control, not
that music can be sent to it or that a Sonance EQ curve is actually in the signal path.
