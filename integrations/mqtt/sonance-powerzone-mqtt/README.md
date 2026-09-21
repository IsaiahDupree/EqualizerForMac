# Sonance PowerZone MQTT bridge

This service discovers Sonance PowerZone Connect amplifiers over `_pasconnect._tcp`, validates the
official installer API, and exposes every physical output through MQTT. It runs on any always-on machine
with Node.js 20 or newer; it does not require Home Assistant or a public cloud service.

## Topics

The amplifier serial is normalized to lowercase for the topic path:

```text
sonance_eq/<serial>/output/<n>/preset/set       command: preset ID or title
sonance_eq/<serial>/output/<n>/preset/state     retained preset title; cleared for unmanaged EQ
sonance_eq/<serial>/output/<n>/attributes       retained JSON device/output state
sonance_eq/<serial>/output/<n>/availability     retained online/offline
sonance_eq/<serial>/output/<n>/error            retained last error, empty after recovery
sonance_eq/bridge/availability                  retained online/offline + MQTT Last Will
```

Accepted commands are `flat`, `bass_boost`, `treble`, `vocal`, `loudness`, `warm_room`, `night`,
`small_speaker`, and `cinema`, or their display titles. Retained commands are deliberately ignored so an
old broker value cannot unexpectedly rewrite an amplifier after a restart.

Home Assistant MQTT discovery is enabled by default. Each output appears as a standard `select` entity
with bridge and amplifier availability. openHAB can use the included [`examples/openhab.things`](examples/openhab.things)
as a Generic MQTT Thing. Node-RED and ioBroker can subscribe and publish to the same documented topics.

## Install

```bash
cd integrations/mqtt/sonance-powerzone-mqtt
npm ci
cp .env.example .env
```

For a local checkout, load `.env` with Node and run:

```bash
npm run start:env
```

For systemd, launchd, Docker, or another process manager that already supplies environment variables,
use `npm start`.

Required configuration:

- `MQTT_URL`: `mqtt://`, `mqtts://`, `ws://`, or `wss://` broker URL.
- `MQTT_USERNAME` and `MQTT_PASSWORD`: broker credentials when configured.

Useful optional configuration:

- `MQTT_CA_FILE`: CA certificate for a private `mqtts://` or `wss://` broker.
- `POWERZONE_HOSTS`: comma-separated manual hosts for routed VLANs where mDNS does not cross.
- `POWERZONE_MDNS=false`: disable discovery when only manual hosts should be used.
- `MQTT_TOPIC_PREFIX`, `HOME_ASSISTANT_DISCOVERY_PREFIX`, and `REFRESH_INTERVAL_MS`.

Use a private broker with ACLs limiting this client to `sonance_eq/#` and, when enabled,
`homeassistant/#`. Use TLS whenever credentials cross an untrusted network. Never expose PowerZone TCP
7621 to the internet; its installer protocol has no authentication.

## Test

```bash
npm test
npm run lint
```

The integration test starts a real in-process MQTT broker and a real TCP protocol server. It verifies
discovery, command delivery, retained state, state readback, failure-safe bypass, offline reporting, and
recovery. It does not replace final testing with the owner's physical amplifier and production broker.
