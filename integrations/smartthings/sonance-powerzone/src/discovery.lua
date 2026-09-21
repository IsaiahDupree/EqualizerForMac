local log = require "log"
local mdns = require "st.mdns"

local powerzone = require "powerzone"

local discovery = {}

local SERVICE_TYPE = "_pasconnect._tcp"
local DOMAIN = "local"

local function service_matches(value)
  return type(value) == "string" and value:lower():find(SERVICE_TYPE, 1, true) ~= nil
end

local function addresses_from_response(response)
  local addresses = {}
  local seen = {}

  local function add(address)
    if powerzone.is_private_ipv4(address) and not seen[address] then
      seen[address] = true
      table.insert(addresses, address)
    end
  end

  for _, found in pairs(response.found or {}) do
    if service_matches(found.service_info and found.service_info.service_type) then
      add(found.host_info and found.host_info.address)
    end
  end

  local service_hosts = {}
  for _, section in ipairs({ response.answers or {}, response.additional or {} }) do
    for _, answer in pairs(section) do
      if answer.kind and answer.kind.SrvRecord and service_matches(answer.name) then
        service_hosts[answer.kind.SrvRecord.target] = true
      end
    end
  end
  for _, section in ipairs({ response.answers or {}, response.additional or {} }) do
    for _, answer in pairs(section) do
      if answer.kind and answer.kind.ARecord and service_hosts[answer.name] then
        add(answer.kind.ARecord.ipv4)
      end
    end
  end
  return addresses
end

local function known_devices(driver)
  local known = {}
  for _, device in ipairs(driver:get_devices()) do
    known[device.device_network_id] = device
    driver.datastore.pending_devices[device.device_network_id] = nil
  end
  return known
end

local function cache_output(driver, address, info, output_id)
  local dni = powerzone.device_network_id(info.serial, output_id)
  driver.datastore.discovery_cache[dni] = {
    address = address,
    serial = info.serial,
    output_id = output_id,
    output_count = info.outputs,
    eq_band_count = info.eq_bands,
    output_name = info.output_names[output_id],
    manufacturer = info.manufacturer,
    model = info.model,
    firmware = info.firmware,
    hardware_id = info.hardware_id,
  }
  return dni, driver.datastore.discovery_cache[dni]
end

local function update_existing(device, cached)
  device:set_field("address", cached.address, { persist = true })
  device:set_field("serial", cached.serial, { persist = true })
  device:set_field("output_id", cached.output_id, { persist = true })
  device:set_field("output_count", cached.output_count, { persist = true })
  device:set_field("eq_band_count", cached.eq_band_count, { persist = true })
  device:set_field("output_name", cached.output_name, { persist = true })
  device:online()
end

function discovery.scan(driver, create_missing)
  local response = mdns.discover(SERVICE_TYPE, DOMAIN) or { found = {} }
  local known = known_devices(driver)
  for _, address in ipairs(addresses_from_response(response)) do
    local info, validation_error = powerzone.validate_server(address)
    if info == nil then
      log.warn_with({ hub_logs = true }, string.format(
        "Ignoring incompatible %s result at %s: %s",
        SERVICE_TYPE,
        address,
        tostring(validation_error)
      ))
    else
      for output_id = 1, info.outputs do
        local dni, cached = cache_output(driver, address, info, output_id)
        local existing = known[dni]
        if existing ~= nil then
          update_existing(existing, cached)
        elseif create_missing and not driver.datastore.pending_devices[dni] then
          local created, create_error = driver:try_create_device({
            type = "LAN",
            device_network_id = dni,
            label = cached.output_name .. " EQ",
            profile = "sonance-powerzone-output",
            manufacturer = cached.manufacturer,
            model = cached.model,
            vendor_provided_label = cached.model .. " " .. cached.output_name,
          })
          if not created then
            log.error_with({ hub_logs = true }, "Failed to create " .. dni .. ": " .. tostring(create_error))
          else
            driver.datastore.pending_devices[dni] = true
          end
        end
      end
    end
  end
end

function discovery.handler(driver, _, should_continue)
  log.info_with({ hub_logs = true }, "Starting Sonance PowerZone mDNS discovery")
  while should_continue() do
    discovery.scan(driver, true)
  end
  log.info_with({ hub_logs = true }, "Sonance PowerZone mDNS discovery ended")
end

return discovery
