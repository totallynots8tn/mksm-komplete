local H = dofile("tests/harness.lua")
local m = H.load(arg[1])

local FIRE = 0x16ED90
local LOADMAP = 0x12883
local CURRENT_MAP = 0x505970
local MGR_PTR = 0x682020
local MGR = 0x200000
local DEF = 0x300000
local ARGS = 0x300100
local ESP = 0xD0000700

H.w32(MGR_PTR, MGR)
H.w32(DEF + 8, ARGS)
H.w32(ESP + 4, DEF)

local function portal(map, trigger)
    H.w32(CURRENT_MAP, map)
    H.w32(ARGS, 99)
    H.w32(ARGS + 4, 7)
    local rec = MGR + trigger * 0xD8
    H.invoke(m, FIRE, { ecx = rec + 0x68 }, function()
        H.invoke(m, LOADMAP, { esp = ESP }, nil)
    end)
    assert(#H.failed == 0, H.failed[1])
    return H.r32(ARGS), H.r32(ARGS + 4)
end

local map, entry = portal(1, 27)
assert(map == 2 and entry == 0, "Wu Shi portal must reload map 1 at its default entry")

map, entry = portal(1, 26)
assert(map == 99 and entry == 7, "other Wu Shi triggers must keep their destination")

map, entry = portal(100, 27)
assert(map == 101 and entry == 0, "Goro portal must reload map 100 and restage its authored encounter")

map, entry = portal(100, 26)
assert(map == 99 and entry == 7, "other Goro's Lair triggers must keep their destination")

map, entry = portal(2, 27)
assert(map == 99 and entry == 7, "trigger 27 outside rift areas must keep its destination")

H.w32(CURRENT_MAP, 1)
H.w32(ARGS, 99)
H.w32(ARGS + 4, 7)
H.invoke(m, LOADMAP, { esp = ESP }, nil)
assert(H.r32(ARGS) == 99 and H.r32(ARGS + 4) == 7, "loadmap outside the portal event must stay vanilla")

print("time rifts: Wu Shi and Goro reloads, authored encounter staging, trigger and map isolation all pass")
