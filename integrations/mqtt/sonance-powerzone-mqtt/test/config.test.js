'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { loadConfig } = require('../src/config');
const { PowerZoneClient } = require('../src/powerzone-client');
const { getPreset, powerZoneBands } = require('../src/presets');

test('configuration accepts secure brokers and explicit routed hosts', () => {
  const config = loadConfig({
    MQTT_URL: 'mqtts://broker.home.example:8883',
    MQTT_USERNAME: 'sonance',
    MQTT_PASSWORD: 'secret',
    POWERZONE_HOSTS: '192.168.10.20, powerzone.local',
    POWERZONE_MDNS: 'false',
  });
  assert.equal(config.mqttUrl, 'mqtts://broker.home.example:8883');
  assert.deepEqual(config.manualHosts, ['192.168.10.20', 'powerzone.local']);
  assert.equal(config.mdnsEnabled, false);
});

test('configuration rejects unsafe MQTT topic wildcards and unsupported URLs', () => {
  assert.throws(() => loadConfig({ MQTT_URL: 'https://broker.example' }), /must use mqtt/);
  assert.throws(() => loadConfig({
    MQTT_URL: 'mqtt://127.0.0.1',
    MQTT_TOPIC_PREFIX: 'sonance_eq/#',
  }), /Invalid MQTT topic prefix/);
});

test('PowerZone client rejects a public target before opening its API', async () => {
  const client = new PowerZoneClient('8.8.8.8');
  await assert.rejects(client.validatedAddresses(), /private or link-local/);
});

test('preset lookup is normalized and every hardware curve preserves headroom', () => {
  assert.equal(getPreset('BASS BOOST').id, 'bass_boost');
  for (const name of ['bass_boost', 'treble', 'vocal', 'loudness', 'warm_room', 'night', 'small_speaker', 'cinema']) {
    const bands = powerZoneBands(name, 10);
    assert.equal(Math.max(...bands.map(band => band.gain)), 0);
  }
});
