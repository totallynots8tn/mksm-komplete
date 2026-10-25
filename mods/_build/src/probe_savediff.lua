-- MKSMK Probe: save-data watcher (diagnostics only, changes nothing).
-- The game manager [0x5ACEBC] is also the save data: event flags at +0x4874,
-- the player character IDs at +0xCC/+0xD0, and (to be found) XP, upgrades and
-- abilities. This script snapshots WATCH_BYTES of it, one slice per frame,
-- then keeps comparing slice by slice. Every dword that changes is recorded
-- with its first value, its latest value and how often it changed. The report
-- (written when the game saves, probe_save.lua) lists them by offset. Unlock an
-- ability, buy an upgrade or gain XP, then save: the offsets that moved are the
-- fields. Matched against archived save.dat files it maps file offsets to
-- memory. A new game manager pointer (new game, load) starts a new baseline.
local GAME_MANAGER = 0x005ACEBC
local CHECK        = 0x0016F4B0   -- runs every frame in gameplay; drives the scan
local FRAME        = 0x005CE878
local WATCH_BYTES  = 0x8000
local SLICE_DWORDS = 256
local CHANGE_CAP   = 600          -- distinct offsets kept

local function ok(p)
    return p >= 0x10000 and p % 4 == 0 and (p < 0x7FFE0000 or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000) or (p >= 0xD0000000 and p < 0xE0000000)
        or (p >= 0xF0000000 and p < 0xF4000000))
end
local function hex(v) return string.format("%X", v) end

local DWORDS = WATCH_BYTES // 4
local base, baseline, built, cursor, last_frame = nil, {}, 0, 0, nil
local changes, change_count, rebases = {}, 0, 0
local done = false

local function step()
    local frame = game.read_u32(FRAME)
    if frame == last_frame then return end
    last_frame = frame
    local gm = game.read_u32(GAME_MANAGER)
    if not ok(gm) then return end
    if gm ~= base then
        base, baseline, built, cursor = gm, {}, 0, 0
        rebases = rebases + 1
    end
    if built < DWORDS then
        local stop = math.min(built + SLICE_DWORDS, DWORDS)
        for i = built, stop - 1 do baseline[i] = game.read_u32(base + i * 4) end
        built = stop
        return
    end
    local stop = math.min(cursor + SLICE_DWORDS, DWORDS)
    for i = cursor, stop - 1 do
        local v = game.read_u32(base + i * 4)
        local c = changes[i]
        if c then
            if v ~= c.last then c.last = v; c.n = c.n + 1 end
        elseif v ~= baseline[i] and change_count < CHANGE_CAP then
            changes[i] = { first = baseline[i], last = v, n = 1 }
            change_count = change_count + 1
        end
    end
    cursor = stop % DWORDS
end

local function report(reason)
    done = true
    local list = {}
    for i in pairs(changes) do list[#list + 1] = i end
    table.sort(list)
    local parts = {}
    for _, i in ipairs(list) do
        local c = changes[i]
        parts[#parts + 1] = "+" .. hex(i * 4) .. ":" .. hex(c.first) .. ">" .. hex(c.last) .. "(" .. c.n .. ")"
    end
    error("SAVEDIFF " .. reason .. " gm=" .. hex(base or 0) .. " rebases=" .. rebases
        .. " watched=" .. hex(built * 4) .. " changed=" .. change_count
        .. " | " .. table.concat(parts, " "), 0)
end

return {
    {   address = CHECK,
        before = function(ctx)
            if not done then step() end
        end },
    {   address = SAVE_GAME,
        before = function(ctx)
            if save_due() and not done and change_count > 0 then report(save_tag("save")) end
        end },
}
