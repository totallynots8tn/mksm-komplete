-- MKSMK Probe: heartbeat (diagnostics only, changes nothing).
-- Every other probe reports at a save, so a soft-lock or crash between statues
-- left no probe data at all (softlock-2039, log 088). This script samples the
-- live state once every SAMPLE_FRAMES gameplay frames: map, XP, the spawner
-- (active, group, spawned), the loaded enemy types and the cleared-waves table,
-- the same fields tools/livemem/peek.py prints. A script can only log once
-- (by failing with error()), so build.py ships copies with HB_INDEX 1..N; copy
-- k reports after k*REPORT_FRAMES gameplay frames with the samples taken since
-- copy k-1 reported, plus any statue saves in that window. Gameplay frames
-- only advance while the game runs (not paused or on menus).
local GAME_MANAGER  = 0x005ACEBC
local CHECK         = 0x0016F4B0   -- runs every frame in gameplay
local HB_SAVE_GAME  = 0x001272A0   -- the statue save write (probe_save.lua)
local FRAME         = 0x005CE878
local MAP           = 0x00505970
local LOADED_TYPES  = 0x006CA69C   -- 6 dwords, -1 = empty
local SPAWNER       = 0x006DBFB0
local WAVES_CLEARED = 0x006C0168   -- 20 x {s16 group, u32 alive, u8 cleared}, 12 apart
local XP            = 0x4940       -- game manager offset (SAVEDIFF / save.dat slot+0x4940)
local HB_INDEX      = 1            -- this copy reports after HB_INDEX*REPORT_FRAMES frames (build.py makes copies)
local SAMPLE_FRAMES = 2500         -- about 40 seconds
local REPORT_FRAMES = 22500        -- about 7.5 minutes; 24 copies fit the 64-script limit

local function hex(v) return string.format("%X", v) end
local function ok(p)
    return p >= 0x10000 and p % 4 == 0 and (p < 0x7FFE0000 or (p >= 0x80000000 and p < 0x84000000))
end

local last_frame, elapsed = nil, 0
local window_start = (HB_INDEX - 1) * REPORT_FRAMES
local samples, saves = {}, 0
local done = false

local function sample(tag)
    local gm = game.read_u32(GAME_MANAGER)
    local xp = ok(gm) and tostring(game.read_u32(gm + XP)) or "-"
    local types = {}
    for i = 0, 5 do
        local t = game.read_u32(LOADED_TYPES + i * 4)
        if t ~= 0xFFFFFFFF then types[#types + 1] = hex(t) end
    end
    local waves = {}
    for i = 0, 19 do
        local a = WAVES_CLEARED + i * 12
        local g = game.read_u16(a)
        if g ~= 0 then
            if g >= 0x8000 then g = g - 0x10000 end
            waves[#waves + 1] = g .. ":" .. game.read_u32(a + 4) .. ":" .. game.read_u8(a + 8)
        end
    end
    samples[#samples + 1] = tag .. elapsed .. " f" .. hex(game.read_u32(FRAME)) .. " m" .. game.read_u32(MAP)
        .. " xp" .. xp .. " sp" .. game.read_u8(SPAWNER + 0x2092A) .. "," .. game.read_u16(SPAWNER + 0x20920)
        .. "," .. game.read_u16(SPAWNER + 0x20922) .. " ty" .. table.concat(types, ",")
        .. " wc[" .. table.concat(waves, " ") .. "]"
end

local function step()
    local frame = game.read_u32(FRAME)
    if frame == last_frame then return end
    last_frame = frame
    elapsed = elapsed + 1
    if elapsed <= window_start then return end
    if elapsed % SAMPLE_FRAMES == 0 then sample("t") end
    if elapsed >= HB_INDEX * REPORT_FRAMES then
        done = true
        error("HEARTBEAT#" .. HB_INDEX .. " frames=" .. elapsed .. " saves=" .. saves
            .. " | " .. table.concat(samples, " | "), 0)
    end
end

return {
    {   address = CHECK,
        before = function(ctx)
            if not done then step() end
        end },
    {   address = HB_SAVE_GAME,
        before = function(ctx)
            if not done and elapsed > window_start then
                saves = saves + 1
                sample("save@")
            end
        end },
}
