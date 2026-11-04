-- XP Shop 0.12: the two built scripts (shop, EX) split the full script's
-- hooks between them, each hook in exactly one, with the EX gameplay hooks
-- in the EX script; tests/upgrade.lua runs the full one (PART "all").
--   lua tests/upgrade_parts.lua <upgrade.lua> <upgrade_ex.lua> <src/upgrade.lua>
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
-- (the source runs with the callgate library in front, as the built scripts do)
local function with_gate(path)
  local src = assert(io.open("src/callgate_lib.lua", "rb")):read("a") .. assert(io.open(path, "rb")):read("a")
  local tmp = os.tmpname()
  assert(io.open(tmp, "wb")):write(src):close()
  local by = H.load(tmp)
  os.remove(tmp)
  return by
end
local shop, ex, all = H.load(arg[1]), H.load(arg[2]), with_gate(arg[3])
local function count(by)
  local n = 0
  for _, list in pairs(by) do n = n + #list end
  return n
end
for address, list in pairs(all) do
  local a, b = shop[address] and #shop[address] or 0, ex[address] and #ex[address] or 0
  assert(a + b == #list and (a == 0 or b == 0),
    string.format("hook %08X: %d in the shop script, %d in the EX script, %d in the full one", address, a, b, #list))
end
assert(count(shop) + count(ex) == count(all), "a built script has a hook the full one doesn't")
local EX = { 0x00129480, 0x001C4A60, 0x00180D30, 0x00153E20, 0x000111C2, 0x00012FD1, 0x0001406B }
for _, address in ipairs(EX) do
  assert(ex[address] and not shop[address], string.format("EX hook %08X not in the EX script alone", address))
end
assert(shop[0x00013A12] and shop[0x00016965] and not ex[0x00016965], "the menu and stamina hooks belong to the shop script")
for _, address in ipairs({ 0x00012284, 0x00012C93, 0x00011C8F, 0x00016AC8, 0x000126E4 }) do
  assert(shop[address] and not ex[address], string.format("gate or meter hook %08X not in the shop script alone", address))
end
print("shop hooks:", count(shop), "EX hooks:", count(ex))
print("PASS xp shop parts")
