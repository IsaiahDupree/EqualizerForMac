local presets = {}

presets.ISO_CENTERS = {
  31.25,
  62.5,
  125.0,
  250.0,
  500.0,
  1000.0,
  2000.0,
  4000.0,
  8000.0,
  16000.0,
}

presets.ORDER = {
  "flat",
  "bass_boost",
  "treble",
  "vocal",
  "loudness",
  "warm_room",
  "night",
  "small_speaker",
  "cinema",
}

presets.DEFINITIONS = {
  flat = { title = "Flat", gains = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
  bass_boost = { title = "Bass Boost", gains = { 6, 5, 4, 2, 0, 0, 0, 0, 0, 0 } },
  treble = { title = "Treble", gains = { 0, 0, 0, 0, 0, 0, 2, 4, 5, 6 } },
  vocal = { title = "Vocal", gains = { -3, -2, -1, 1, 3, 4, 3, 1, 0, -1 } },
  loudness = { title = "Loudness", gains = { 6, 4, 2, 0, -1, -1, 0, 2, 4, 5 } },
  warm_room = { title = "Warm Room", gains = { 2, 2, 1.5, 1, 0, -0.5, -1, -1, -0.5, 0 } },
  night = { title = "Night", gains = { -8, -6, -3, -1, 1, 2, 2, 1, -1, -3 } },
  small_speaker = { title = "Small Speaker", gains = { -12, -8, -4, 0, 2, 3, 2, 1, 0, -1 } },
  cinema = { title = "Cinema", gains = { 4, 3, 1, 0, -1, 1, 3, 2, 2, 1 } },
}

presets.COMPONENT_TO_PRESET = {
  main = "flat",
  bassBoost = "bass_boost",
  treble = "treble",
  vocal = "vocal",
  loudness = "loudness",
  warmRoom = "warm_room",
  night = "night",
  smallSpeaker = "small_speaker",
  cinema = "cinema",
}

local function round(value, decimals)
  local scale = 10 ^ decimals
  return math.floor(value * scale + 0.5) / scale
end

function presets.powerzone_bands(preset_id, band_count)
  local definition = presets.DEFINITIONS[preset_id]
  if definition == nil then
    return nil, "Unknown Sonance EQ preset: " .. tostring(preset_id)
  end
  if type(band_count) ~= "number" or band_count % 1 ~= 0 or band_count < 1 then
    return nil, "PowerZone must expose at least one output EQ band"
  end

  local has_gain = false
  for _, gain in ipairs(definition.gains) do
    if gain ~= 0 then
      has_gain = true
      break
    end
  end
  if not has_gain then
    return {}
  end

  local count = math.min(band_count, #presets.ISO_CENTERS)
  local indices = {}
  local q
  if count == 1 then
    indices[1] = math.floor(#presets.ISO_CENTERS / 2) + 1
    q = 0.4
  else
    for index = 1, count do
      local source_index = math.floor(((index - 1) * (#presets.ISO_CENTERS - 1) / (count - 1)) + 0.5) + 1
      table.insert(indices, source_index)
    end
    local bandwidth_octaves = (#presets.ISO_CENTERS - 1) / (count - 1)
    local ratio = 2 ^ bandwidth_octaves
    q = math.max(0.4, math.sqrt(ratio) / (ratio - 1))
  end

  local headroom = 0
  for _, source_index in ipairs(indices) do
    headroom = math.max(headroom, definition.gains[source_index])
  end

  local bands = {}
  for _, source_index in ipairs(indices) do
    table.insert(bands, {
      type = "PARAMETRIC",
      frequency = presets.ISO_CENTERS[source_index],
      q = round(q, 3),
      gain = definition.gains[source_index] - headroom,
    })
  end
  return bands
end

return presets
