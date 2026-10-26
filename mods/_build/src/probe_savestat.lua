-- MKSMK Probe: per-save stats (diagnostics only, changes nothing).
-- SAVEDIFF reports at saves 1-3 only, and never states the XP balance or which
-- slot was written; both had to be worked out from save.dat diffs. This copy
-- logs, at its SAVE_INDEX-th save of the session, the values that save writes:
-- playtime (+0x0), XP balance (+0x4940), the upgrade counters (+0xDC, +0x1C4,
-- +0x1D0), the health-upgrade count (+0xE0) and the characters (+0xCC/+0xD0) of the game manager, which uses the
-- same layout as a save.dat slot. The playtime matches the slot label
-- ("CHAR.MAP.PLAYTIME") of the slot written. The save routine's ecx and first
-- stack arguments are logged raw: the slot index is likely among them.
-- build.py ships copies with SAVE_INDEX 1..N.
-- 0.12 adds, per player p (P0/P1 groups): XP (+0x4940+p*0x50), meter value
-- (f32 +0x4954+p*0x50) and level (+0x4978+p*0x50), the EX flag bytes (level
-- slots 19-22) and slot 27 (mgr+0x1C4+p*0x1C+slot), and current/max health
-- (actor +0x368/+0x370); plus max health (+0x94) and the area's health level
-- (+0x90), and the fatality counters: discovered [0x4DFC1C], performed
-- [0x4DF5D8] (does the discovered list survive a reload?).
local GAME_MANAGER = 0x005ACEBC
local FRAME        = 0x005CE878
local MAP          = 0x00505970
local CHAR_TABLE   = 0x005D1AB8    -- player entities, 0x3238 apart; actor at +0x200
local FAT_FOUND    = 0x004DFC1C
local FAT_DONE     = 0x004DF5D8

local function hex(v) return string.format("%X", v) end
local function ok(p)
    return p >= 0x10000 and p % 4 == 0 and (p < 0x7FFE0000 or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xD0000000 and p < 0xE0000000))
end

local done = false

local function player(gm, p)
    local slots = gm + 0x1C4 + p * 0x1C
    local ex = {}
    for s = 19, 22 do ex[#ex + 1] = game.read_u8(slots + s) end
    local actor = game.read_u32(CHAR_TABLE + p * 0x3238 + 0x200)
    local hp = ok(actor) and (game.read_u32(actor + 0x368) .. "/" .. game.read_u32(actor + 0x370)) or "-"
    return " P" .. p .. "[xp=" .. game.read_u32(gm + 0x4940 + p * 0x50)
        .. " mv=" .. math.floor(game.read_f32(gm + 0x4954 + p * 0x50))
        .. " ml=" .. game.read_u32(gm + 0x4978 + p * 0x50)
        .. " ex=" .. table.concat(ex) .. " s27=" .. game.read_u8(slots + 27) .. " hp=" .. hp .. "]"
end

local function report(ctx)
    done = true
    local gm = game.read_u32(GAME_MANAGER)
    local fields = "gm=" .. hex(gm)
    if ok(gm) then
        fields = fields .. " playtime=" .. hex(game.read_u32(gm)) .. " xp=" .. game.read_u32(gm + 0x4940)
            .. " chars=" .. hex(game.read_u32(gm + 0xCC)) .. "," .. hex(game.read_u32(gm + 0xD0))
            .. " +DC=" .. hex(game.read_u32(gm + 0xDC)) .. " +E0=" .. hex(game.read_u32(gm + 0xE0)) .. " +1C4=" .. hex(game.read_u32(gm + 0x1C4))
            .. " +1D0=" .. hex(game.read_u32(gm + 0x1D0))
            .. player(gm, 0) .. player(gm, 1)
            .. " maxhp=" .. game.read_u32(gm + 0x94) .. " hplvl=" .. game.read_u32(gm + 0x90)
            .. " fat=" .. game.read_u32(FAT_FOUND) .. "/" .. game.read_u32(FAT_DONE)
    end
    local args = {}
    if ok(ctx.esp) then
        for i = 1, 4 do args[#args + 1] = hex(game.read_u32(ctx.esp + i * 4)) end
    end
    error("SAVESTAT " .. save_tag("save") .. " frame=" .. hex(game.read_u32(FRAME))
        .. " map=" .. game.read_u32(MAP) .. " " .. fields
        .. " ecx=" .. hex(ctx.ecx or 0) .. " args=" .. table.concat(args, ","), 0)
end

return {
    {   address = SAVE_GAME,
        before = function(ctx)
            if not done and save_due() then report(ctx) end
        end },
}
