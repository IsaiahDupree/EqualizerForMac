# Sonance EQ for SmartThings

[`sonance-powerzone`](sonance-powerzone/README.md) is a native local SmartThings Edge driver. It discovers
PowerZone amplifiers over mDNS, creates one speaker device per physical output, exposes all nine presets
as standard Automation-compatible actions, and reports the currently programmed curve.

It does not require Home Assistant, a cloud webhook, OAuth credentials, or a custom SmartThings
capability. Uploading the already build-valid package to a channel still requires the owner's SmartThings
developer login and an enrolled hub.
