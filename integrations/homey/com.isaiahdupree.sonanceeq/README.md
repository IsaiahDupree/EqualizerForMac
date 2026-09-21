# Sonance EQ for Homey Pro

This native Homey SDK v3 app discovers Sonance PowerZone Connect and Connect PRO amplifiers through
their official `_pasconnect._tcp` mDNS service. Pairing creates one Homey speaker device per physical
amplifier output, using the installer-defined output names.

Each output exposes a standard Homey picker and Flow action for nine Sonance EQ presets. The app writes
the physical output user-EQ stage over the official local TCP API on port `7621`, so the curve applies to
every source routed through that output—not only streams launched by Homey.

## Requirements

- Homey Pro running Homey `12.0.1` or newer. Homey Cloud/Homey Bridge cannot access LAN mDNS services.
- A supported Sonance PowerZone amplifier on the same private network as Homey Pro.
- `_pasconnect._tcp` discovery and TCP port `7621` permitted between Homey Pro and the amplifier.

## Install for development

```bash
cd integrations/homey/com.isaiahdupree.sonanceeq
npm install
npm test
npm run validate
homey app run
```

In Homey, add **Sonance EQ → PowerZone output**. Select one or more discovered outputs. The paired tile
contains the preset picker; Advanced Flow also provides **Set EQ preset**.

The device settings retain the verified private host and API port. mDNS automatically follows DHCP
address changes, but the host can also be corrected manually. A replacement device is rejected unless
its serial number matches the originally paired amplifier.

## Safety model

- DNS is resolved once, every answer must be private/link-local, and the connection is pinned to a
  validated address to prevent DNS rebinding.
- Commands are length-limited, newline-free, and serialized per output device.
- Positive EQ gain is normalized to `0 dB` so presets do not consume calibrated amplifier headroom.
- The output EQ stage is bypassed while registers change. A failed transaction remains bypassed rather
  than leaving a partially programmed live curve.
- The PowerZone protocol is unauthenticated. Never forward port `7621`; isolate installer/control traffic
  with normal LAN/VLAN policy.

This app controls EQ and does not transport audio. Chromecast, Google Home, AirPlay, Sonos, HEOS,
Bluetooth, HDMI, optical, analog, Dante, and other sources continue to use their native playback path;
the PowerZone output stage applies downstream when that audio is routed through the amplifier.
