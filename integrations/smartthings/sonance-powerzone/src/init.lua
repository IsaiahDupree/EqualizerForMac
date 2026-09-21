local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

local discovery = require "discovery"
local powerzone = require "powerzone"
local presets = require "presets"

local REFRESH_INTERVAL_SECONDS = 300

local function load_cached_fields(driver, device)
  local cached = driver.datastore.discovery_cache[device.device_network_id]
  if cached == nil then
    return
  end
  device:set_field("address", cached.address, { persist = true })
  device:set_field("serial", cached.serial, { persist = true })
  device:set_field("output_id", cached.output_id, { persist = true })
  device:set_field("output_count", cached.output_count, { persist = true })
  device:set_field("eq_band_count", cached.eq_band_count, { persist = true })
  device:set_field("output_name", cached.output_name, { persist = true })
end

local function emit_preset(device, preset_id)
  local definition = presets.DEFINITIONS[preset_id]
  local title = definition and definition.title or "Custom / unmanaged EQ"
  device:emit_event(capabilities.audioTrackData.audioTrackData({
    title = title,
    artist = "Sonance EQ preset",
    album = device:get_field("output_name") or device.label,
    mediaSource = "PowerZone output DSP",
  }))
end

local function refresh(_, device)
  local address = device:get_field("address")
  local output_id = device:get_field("output_id")
  local output_count = device:get_field("output_count")
  local eq_band_count = device:get_field("eq_band_count")
  if address == nil or output_id == nil or output_count == nil or eq_band_count == nil then
    device:offline()
    return
  end

  local preset_id, err = powerzone.read_preset(address, output_id, output_count, eq_band_count)
  if err ~= nil then
    device.log.warn_with({ hub_logs = true }, "PowerZone refresh failed: " .. tostring(err))
    device:offline()
    return
  end
  emit_preset(device, preset_id)
  device:online()
end

local function apply_preset(_, device, command)
  local preset_id = presets.COMPONENT_TO_PRESET[command.component]
  if preset_id == nil then
    device.log.error_with({ hub_logs = true }, "Unknown preset component: " .. tostring(command.component))
    return
  end
  local applied, err = powerzone.apply_preset(
    device:get_field("address"),
    device:get_field("output_id"),
    device:get_field("output_count"),
    device:get_field("eq_band_count"),
    preset_id
  )
  if not applied then
    device.log.error_with({ hub_logs = true }, "PowerZone preset failed: " .. tostring(err))
    device:offline()
    return
  end
  emit_preset(device, preset_id)
  device:online()
end

local function device_init(driver, device)
  if device:get_field("sonance_initialized") then
    return
  end
  device:set_field("sonance_initialized", true)
  driver.datastore.pending_devices[device.device_network_id] = nil
  load_cached_fields(driver, device)
  device.thread:call_with_delay(0, function()
    refresh(driver, device)
  end)
  device.thread:call_on_schedule(
    REFRESH_INTERVAL_SECONDS,
    function()
      refresh(driver, device)
    end,
    device.id .. "-powerzone-refresh"
  )
end

local sonance_driver = Driver("sonance-powerzone-eq", {
  discovery = discovery.handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_init,
  },
  capability_handlers = {
    [capabilities.momentary.ID] = {
      [capabilities.momentary.commands.push.NAME] = apply_preset,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh,
    },
  },
})

sonance_driver.datastore.discovery_cache = sonance_driver.datastore.discovery_cache or {}
sonance_driver.datastore.pending_devices = sonance_driver.datastore.pending_devices or {}
sonance_driver:call_on_schedule(REFRESH_INTERVAL_SECONDS, function(driver)
  discovery.scan(driver, false)
end, "powerzone-rediscovery")

log.info("Starting Sonance PowerZone EQ Edge driver")
sonance_driver:run()
