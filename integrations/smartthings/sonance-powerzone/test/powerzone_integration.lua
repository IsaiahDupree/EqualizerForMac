local root = arg[0]:match("^(.*)/test/") or "."
package.path = table.concat({
  root .. "/test/compat/?.lua",
  root .. "/test/compat/?/init.lua",
  root .. "/src/?.lua",
  package.path,
}, ";")

local powerzone = require "powerzone"
local presets = require "presets"

local address = assert(os.getenv("POWERZONE_TEST_HOST"))
local port = assert(tonumber(os.getenv("POWERZONE_TEST_PORT")))
local mode = arg[1] or "success"

powerzone.API_PORT = port

assert(powerzone.is_private_ipv4("127.0.0.1"))
assert(powerzone.is_private_ipv4("192.168.1.10"))
assert(not powerzone.is_private_ipv4("1.1.1.1"))
assert(powerzone.validate_command("GET API_VERSION"))
assert(not powerzone.validate_command("GET API_VERSION\nSET OUT-1.EQ.BYPASS 0"))

local four_bands = assert(presets.powerzone_bands("bass_boost", 4))
assert(#four_bands == 4)
assert(four_bands[1].frequency == 31.25)
assert(four_bands[2].frequency == 250)
assert(four_bands[3].frequency == 2000)
assert(four_bands[4].frequency == 16000)
local max_gain = -math.huge
for _, band in ipairs(four_bands) do
  max_gain = math.max(max_gain, band.gain)
end
assert(max_gain == 0)

local info = assert(powerzone.validate_server(address))
assert(info.serial == "PZ-TEST-0001")
assert(info.outputs == 4)
assert(info.eq_bands == 4)
assert(info.output_names[2] == "Zone 2")

if mode == "failure" then
  local applied, err = powerzone.apply_preset(address, 1, info.outputs, info.eq_bands, "vocal")
  assert(not applied)
  assert(err:find("Test rejection", 1, true))
  io.write("failure path passed\n")
  return
end

assert(powerzone.apply_preset(address, 2, info.outputs, info.eq_bands, "vocal"))
assert(powerzone.read_preset(address, 2, info.outputs, info.eq_bands) == "vocal")
assert(powerzone.apply_preset(address, 2, info.outputs, info.eq_bands, "flat"))
assert(powerzone.read_preset(address, 2, info.outputs, info.eq_bands) == "flat")
assert(not powerzone.apply_preset(address, 5, info.outputs, info.eq_bands, "vocal"))

io.write("success path passed\n")
