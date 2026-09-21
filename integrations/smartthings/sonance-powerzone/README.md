# Sonance PowerZone EQ for SmartThings Edge

This Lua Edge driver runs locally on a SmartThings hub. It discovers the official Sonance
`_pasconnect._tcp` mDNS service, verifies the PowerZone installer API on TCP port `7621`, and creates
one SmartThings speaker device per physical amplifier output.

Each output device uses standard SmartThings capabilities only:

- Nine `momentary` actions—Flat, Bass Boost, Treble, Vocal, Loudness, Warm Room, Night, Small Speaker,
  and Cinema—work in the device detail view and SmartThings Automations.
- `audioTrackData` reports the currently detected preset and output name.
- `refresh` re-reads the real amplifier registers.

No custom-capability namespace, cloud webhook, OAuth server, Home Assistant instance, or public inbound
port is required.

## Build and test

The integration test uses LuaSocket only as a compatibility transport and exercises the production Lua
client against a real local TCP server. The Edge runtime supplies the API-compatible `cosock.socket`.

```bash
cd integrations/smartthings/sonance-powerzone
npm test
npm run lint
npm run build
```

Use a Lua 5.3-compatible interpreter and LuaSocket. On Ubuntu CI the packages are `lua5.3` and
`lua-socket`. `npm run build` uses the pinned official SmartThings CLI and writes
`/tmp/sonance-powerzone-edge.zip` without uploading it.

## Install on a hub

Uploading requires a SmartThings developer account, channel, and enrolled hub:

```bash
npx @smartthings/cli@2.1.2 edge:drivers:package . --assign --install
```

After the driver is installed, run **Scan nearby** in SmartThings. PowerZone output devices appear with
their installer-defined names.

## Safety and interoperability

- The driver accepts only RFC1918, loopback, or IPv4 link-local targets returned by mDNS.
- Commands are length-limited and newline-free.
- Positive EQ gain is normalized to `0 dB`.
- The output EQ is bypassed for the entire write transaction; a failure leaves it safely bypassed.
- The installer API is unauthenticated. Never port-forward `7621`; use normal LAN/VLAN isolation.

This controls downstream output DSP, not playback transport. Cast, AirPlay, Spotify Connect, HDMI,
optical, analog, Bluetooth, Dante, and other sources retain their own playback controls while receiving
the selected curve whenever routed through the PowerZone output.
