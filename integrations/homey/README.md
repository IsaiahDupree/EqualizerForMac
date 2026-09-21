# Sonance EQ home integrations

- [`com.isaiahdupree.sonanceeq`](com.isaiahdupree.sonanceeq/README.md) is the native Homey Pro app.
  It discovers PowerZone amplifiers locally and exposes every physical output as a preset picker and
  Advanced Flow target.
- The [Home Assistant integration](../home_assistant/README.md) remains the broader routing, Music
  Assistant, Google Cast, and bridge control plane.

Both packages use the same nine curves, PowerZone register contract, headroom normalization, private-LAN
restriction, and fail-safe bypass transaction.
