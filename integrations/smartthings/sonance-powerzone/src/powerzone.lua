local socket = require "cosock.socket"

local presets = require "presets"

local powerzone = {}

local TIMEOUT_SECONDS = 5
local MAX_COMMAND_BYTES = 8192
local MAX_LINE_BYTES = 16384
local MAX_RESPONSE_LINES = 4096
local MAX_OUTPUTS = 128
local MAX_EQ_BANDS = 128

powerzone.API_PORT = 7621

local function close_socket(sock)
  if sock ~= nil then
    pcall(function()
      sock:close()
    end)
  end
end

function powerzone.is_private_ipv4(address)
  if type(address) ~= "string" then
    return false
  end
  local a, b, c, d = address:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if a == nil or b == nil or c == nil or d == nil then
    return false
  end
  if a > 255 or b > 255 or c > 255 or d > 255 then
    return false
  end
  return a == 10
    or a == 127
    or (a == 169 and b == 254)
    or (a == 172 and b >= 16 and b <= 31)
    or (a == 192 and b == 168)
end

function powerzone.validate_command(command)
  if type(command) ~= "string" then
    return nil, "PowerZone command must be a string"
  end
  local normalized = command:match("^%s*(.-)%s*$")
  if normalized == "" or normalized:find("\n", 1, true) or normalized:find("\r", 1, true) then
    return nil, "PowerZone commands must be one non-empty line"
  end
  if #normalized > MAX_COMMAND_BYTES then
    return nil, "PowerZone command exceeds the API size limit"
  end
  return normalized
end

local function decode_value(raw_value)
  local value = raw_value:match("^%s*(.-)%s*$")
  if #value >= 2 and value:sub(1, 1) == "\"" and value:sub(-1) == "\"" then
    return value:sub(2, -2)
  end
  return tonumber(value) or value
end

local function send_all(sock, payload)
  local offset = 1
  while offset <= #payload do
    local sent, err, partial = sock:send(payload:sub(offset))
    if sent ~= nil then
      offset = offset + sent
    elseif type(partial) == "number" and partial > 0 then
      offset = offset + partial
    else
      return nil, err or "socket send failed"
    end
  end
  return true
end

function powerzone.execute(address, commands)
  if not powerzone.is_private_ipv4(address) then
    return nil, "PowerZone control is restricted to private or link-local IPv4 addresses"
  end
  if type(commands) ~= "table" or #commands == 0 then
    return nil, "At least one PowerZone command is required"
  end

  local normalized_commands = {}
  for _, command in ipairs(commands) do
    local normalized, validation_error = powerzone.validate_command(command)
    if normalized == nil then
      return nil, validation_error
    end
    table.insert(normalized_commands, normalized)
  end

  local sock, socket_error = socket.tcp()
  if sock == nil then
    return nil, "Cannot create PowerZone socket: " .. tostring(socket_error)
  end
  sock:settimeout(TIMEOUT_SECONDS)
  local connected, connect_error = sock:connect(address, powerzone.API_PORT)
  if connected == nil then
    close_socket(sock)
    return nil, string.format(
      "Cannot reach PowerZone at %s:%d: %s",
      address,
      powerzone.API_PORT,
      tostring(connect_error)
    )
  end

  local responses = {}
  for _, command in ipairs(normalized_commands) do
    local sent, send_error = send_all(sock, command .. "\n")
    if sent == nil then
      close_socket(sock)
      return nil, "PowerZone send failed: " .. tostring(send_error)
    end

    local values = {}
    local response_lines = 0
    while true do
      local line, receive_error = sock:receive("*l")
      if line == nil then
        close_socket(sock)
        return nil, "PowerZone receive failed: " .. tostring(receive_error)
      end
      response_lines = response_lines + 1
      if #line > MAX_LINE_BYTES or response_lines > MAX_RESPONSE_LINES then
        close_socket(sock)
        return nil, "PowerZone response exceeds the safety limit"
      end

      if line == "*" .. command then
        table.insert(responses, values)
        break
      elseif line:sub(1, 1) == "#" then
        local detail = line:match("|(.+)$") or line:sub(2)
        close_socket(sock)
        return nil, string.format("PowerZone rejected %s: %s", command, detail)
      elseif line:sub(1, 1) == "+" then
        local register, value = line:match("^%+([^ ]+) (.*)$")
        if register ~= nil then
          values[register] = decode_value(value)
        end
      end
    end
  end

  close_socket(sock)
  return responses
end

function powerzone.validate_server(address)
  local responses, err = powerzone.execute(address, {
    "GET API_VERSION",
    "GET SYSTEM.DEVICE.*",
    "GET OUT.COUNT",
    "GET OUT.EQ.COUNT",
    "GET OUT-*.NAME",
  })
  if responses == nil then
    return nil, err
  end

  local api, device, outputs, eq_bands, output_names = table.unpack(responses)
  local info = {
    api_version = tostring(api.API_VERSION or ""),
    serial = tostring(device["SYSTEM.DEVICE.SERIAL"] or ""),
    outputs = tonumber(outputs["OUT.COUNT"]),
    eq_bands = tonumber(eq_bands["OUT.EQ.COUNT"]),
    manufacturer = tostring(device["SYSTEM.DEVICE.VENDOR_NAME"] or "Sonance"),
    model = tostring(device["SYSTEM.DEVICE.MODEL_NAME"] or "PowerZone"),
    firmware = tostring(device["SYSTEM.DEVICE.FIRMWARE"] or ""),
    hardware_id = tostring(device["SYSTEM.DEVICE.HWID"] or ""),
    output_names = {},
  }
  if info.api_version == "" or info.serial == "" or info.outputs == nil or info.eq_bands == nil then
    return nil, "The device did not return the required PowerZone EQ registers"
  end
  if info.outputs % 1 ~= 0 or info.eq_bands % 1 ~= 0
    or info.outputs < 1 or info.outputs > MAX_OUTPUTS
    or info.eq_bands < 1 or info.eq_bands > MAX_EQ_BANDS then
    return nil, "The PowerZone device exposes no usable output EQ"
  end
  for output_id = 1, info.outputs do
    info.output_names[output_id] = tostring(output_names["OUT-" .. output_id .. ".NAME"] or "Output " .. output_id)
  end
  return info
end

local function validate_output(output_id, output_count, eq_band_count)
  output_id = tonumber(output_id)
  output_count = tonumber(output_count)
  eq_band_count = tonumber(eq_band_count)
  if output_id == nil or output_count == nil or output_id % 1 ~= 0
    or output_id < 1 or output_id > output_count then
    return nil, string.format("Output %s is outside this amplifier's range", tostring(output_id))
  end
  if eq_band_count == nil or eq_band_count % 1 ~= 0
    or eq_band_count < 1 or eq_band_count > MAX_EQ_BANDS then
    return nil, "PowerZone EQ band count is invalid"
  end
  return output_id, output_count, eq_band_count
end

function powerzone.apply_preset(address, output_id, output_count, eq_band_count, preset_id)
  local normalized_output, validation_error, normalized_band_count = validate_output(
    output_id,
    output_count,
    eq_band_count
  )
  if normalized_output == nil then
    return nil, validation_error
  end
  local bands, preset_error = presets.powerzone_bands(preset_id, normalized_band_count)
  if bands == nil then
    return nil, preset_error
  end

  local root = "OUT-" .. normalized_output .. ".EQ"
  if #bands == 0 then
    local responses, err = powerzone.execute(address, { "SET " .. root .. ".BYPASS 1" })
    if responses == nil then
      return nil, err
    end
    return true
  end

  local commands = { "SET " .. root .. ".BYPASS 1" }
  for band_id, band in ipairs(bands) do
    local prefix = root .. "-" .. band_id
    table.insert(commands, "SET " .. prefix .. ".TYPE " .. band.type)
    table.insert(commands, string.format("SET %s.FREQ %.2f", prefix, band.frequency))
    table.insert(commands, string.format("SET %s.Q %.3f", prefix, band.q))
    table.insert(commands, string.format("SET %s.GAIN %.2f", prefix, band.gain))
    table.insert(commands, "SET " .. prefix .. ".BYPASS 0")
  end
  for band_id = #bands + 1, normalized_band_count do
    table.insert(commands, "SET " .. root .. "-" .. band_id .. ".BYPASS 1")
  end
  table.insert(commands, "SET " .. root .. ".BYPASS 0")

  local responses, err = powerzone.execute(address, commands)
  if responses == nil then
    return nil, err
  end
  return true
end

local function as_boolean(value)
  if type(value) == "string" then
    local normalized = value:lower():match("^%s*(.-)%s*$")
    return normalized == "1" or normalized == "true" or normalized == "on" or normalized == "yes"
  end
  return not not value and value ~= 0
end

local function matches_bands(root, expected, band_count, values)
  for band_id = 1, band_count do
    local prefix = root .. "-" .. band_id
    if band_id > #expected then
      if not as_boolean(values[prefix .. ".BYPASS"]) then
        return false
      end
    else
      local band = expected[band_id]
      local frequency = tonumber(values[prefix .. ".FREQ"])
      local q = tonumber(values[prefix .. ".Q"])
      local gain = tonumber(values[prefix .. ".GAIN"])
      if as_boolean(values[prefix .. ".BYPASS"])
        or values[prefix .. ".TYPE"] ~= band.type
        or frequency == nil or math.abs(frequency - band.frequency) > 0.1
        or q == nil or math.abs(q - band.q) > 0.01
        or gain == nil or math.abs(gain - band.gain) > 0.05 then
        return false
      end
    end
  end
  return true
end

function powerzone.read_preset(address, output_id, output_count, eq_band_count)
  local normalized_output, validation_error, normalized_band_count = validate_output(
    output_id,
    output_count,
    eq_band_count
  )
  if normalized_output == nil then
    return nil, validation_error
  end

  local root = "OUT-" .. normalized_output .. ".EQ"
  local commands = { "GET " .. root .. ".BYPASS" }
  for band_id = 1, normalized_band_count do
    local prefix = root .. "-" .. band_id
    table.insert(commands, "GET " .. prefix .. ".TYPE")
    table.insert(commands, "GET " .. prefix .. ".FREQ")
    table.insert(commands, "GET " .. prefix .. ".Q")
    table.insert(commands, "GET " .. prefix .. ".GAIN")
    table.insert(commands, "GET " .. prefix .. ".BYPASS")
  end

  local responses, err = powerzone.execute(address, commands)
  if responses == nil then
    return nil, err
  end
  local values = {}
  for _, response in ipairs(responses) do
    for register, value in pairs(response) do
      values[register] = value
    end
  end
  if as_boolean(values[root .. ".BYPASS"]) then
    return "flat"
  end
  for _, preset_id in ipairs(presets.ORDER) do
    if preset_id ~= "flat" then
      local expected = presets.powerzone_bands(preset_id, normalized_band_count)
      if matches_bands(root, expected, normalized_band_count, values) then
        return preset_id
      end
    end
  end
  return nil
end

function powerzone.device_network_id(serial, output_id)
  local safe_serial = tostring(serial):gsub("[^%w_.-]", "-")
  return string.format("%s-output-%d", safe_serial, tonumber(output_id))
end

return powerzone
