'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { ISO_CENTERS, PRESETS, powerZoneBands } = require('../lib/presets');

test('all nine Sonance curves have stable IDs and ten source bands', () => {
  assert.equal(PRESETS.length, 9);
  assert.equal(new Set(PRESETS.map(preset => preset.id)).size, 9);
  for (const preset of PRESETS) assert.equal(preset.gains.length, ISO_CENTERS.length);
});

test('PowerZone adaptation respects band count and preserves headroom', () => {
  assert.deepEqual(powerZoneBands('flat', 4), []);
  const fourBand = powerZoneBands('bass_boost', 4);
  assert.deepEqual(fourBand.map(band => band.frequency), [31.25, 250, 2000, 16000]);
  assert.equal(Math.max(...fourBand.map(band => band.gain)), 0);
  assert.ok(fourBand.every(band => band.q >= 0.4 && band.q <= 30));

  const tenBand = powerZoneBands('vocal', 20);
  assert.equal(tenBand.length, ISO_CENTERS.length);
  assert.deepEqual(tenBand.map(band => band.frequency), ISO_CENTERS);
  assert.equal(Math.max(...tenBand.map(band => band.gain)), 0);
});
