'use strict';

const ISO_CENTERS = Object.freeze([
  31.25,
  62.5,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
]);

const PRESETS = Object.freeze([
  { id: 'flat', title: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { id: 'bass_boost', title: 'Bass Boost', gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0] },
  { id: 'treble', title: 'Treble', gains: [0, 0, 0, 0, 0, 0, 2, 4, 5, 6] },
  { id: 'vocal', title: 'Vocal', gains: [-3, -2, -1, 1, 3, 4, 3, 1, 0, -1] },
  { id: 'loudness', title: 'Loudness', gains: [6, 4, 2, 0, -1, -1, 0, 2, 4, 5] },
  { id: 'warm_room', title: 'Warm Room', gains: [2, 2, 1.5, 1, 0, -0.5, -1, -1, -0.5, 0] },
  { id: 'night', title: 'Night', gains: [-8, -6, -3, -1, 1, 2, 2, 1, -1, -3] },
  { id: 'small_speaker', title: 'Small Speaker', gains: [-12, -8, -4, 0, 2, 3, 2, 1, 0, -1] },
  { id: 'cinema', title: 'Cinema', gains: [4, 3, 1, 0, -1, 1, 3, 2, 2, 1] },
]);

const PRESET_BY_ID = new Map(PRESETS.map(preset => [preset.id, preset]));
const PRESET_BY_TITLE = new Map(PRESETS.map(preset => [preset.title, preset]));

function getPreset(name) {
  const preset = PRESET_BY_ID.get(name) || PRESET_BY_TITLE.get(name);
  if (!preset) {
    throw new RangeError(`Unknown Sonance EQ preset: ${name}`);
  }
  return preset;
}

function powerZoneBands(name, bandCount) {
  if (!Number.isInteger(bandCount) || bandCount < 1) {
    throw new RangeError('PowerZone must expose at least one output EQ band');
  }

  const { gains } = getPreset(name);
  if (!gains.some(gain => gain !== 0)) {
    return [];
  }

  const count = Math.min(bandCount, ISO_CENTERS.length);
  let indices;
  let q;
  if (count === 1) {
    indices = [Math.floor(ISO_CENTERS.length / 2)];
    q = 0.4;
  } else {
    indices = Array.from({ length: count }, (_, index) => (
      Math.round(index * (ISO_CENTERS.length - 1) / (count - 1))
    ));
    const bandwidthOctaves = (ISO_CENTERS.length - 1) / (count - 1);
    const ratio = 2 ** bandwidthOctaves;
    q = Math.max(0.4, Math.sqrt(ratio) / (ratio - 1));
  }

  const headroom = Math.max(0, ...indices.map(index => gains[index]));
  return indices.map(index => ({
    type: 'PARAMETRIC',
    frequency: ISO_CENTERS[index],
    q: Math.round(q * 1000) / 1000,
    gain: gains[index] - headroom,
  }));
}

module.exports = {
  ISO_CENTERS,
  PRESETS,
  getPreset,
  powerZoneBands,
};
