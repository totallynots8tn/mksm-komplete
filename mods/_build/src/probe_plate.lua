local NAMES = {
    [0x110CD]="musicenable", [0x1116D]="setfatalitylevel", [0x112C1]="TYMFailRST",
    [0x114A1]="CharLocked", [0x114D3]="animstreaminit", [0x114EC]="minimapobj",
    [0x115F5]="onvsroundend", [0x116A9]="dyncollidebound", [0x117EE]="isvs", [0x1183E]="onbreak",
    [0x118D4]="exitgame", [0x11938]="addstonepower", [0x11A46]="SmokeComplete",
    [0x11A82]="onvsroundstart", [0x11AC8]="isinreaction", [0x11C1C]="MapLocked",
    [0x11C8F]="weaponspawn", [0x11D7A]="spawntutorial", [0x11E51]="Fatalityused",
    [0x121B7]="weaponhide", [0x1233D]="audiostreamdelete", [0x12423]="spawnpickup",
    [0x12847]="messagetext", [0x12860]="holdingweapon", [0x1286F]="mkapowerup", [0x12883]="loadmap",
    [0x128B0]="healthupgrade", [0x12900]="applyforce", [0x12919]="xbox", [0x1296E]="hideallexcept",
    [0x12B21]="unlockendofgame", [0x12B35]="ps2", [0x12B76]="VS_player_fall",
    [0x12C48]="startscorp", [0x12C75]="fatalitystream", [0x12E55]="istwoplayer",
    [0x12E5F]="spawncontainers", [0x12E8C]="demo", [0x13134]="gameevent", [0x1321A]="kilchrefcts",
    [0x13292]="deathphase", [0x132D8]="ignoreaudiostreamdelete", [0x1336E]="dropweapon",
    [0x13382]="isfatalityfull", [0x133D7]="pstcharstats", [0x134F9]="spawnexperience",
    [0x1358A]="fatalityoff", [0x13616]="musicintensity", [0x136CA]="unlockchar",
    [0x13819]="setfatalityAmount", [0x13855]="onvsmatchend", [0x1398B]="TYMWinID",
    [0x13A17]="fatality", [0x13A53]="addexperience", [0x13D0F]="MovieLocked",
    [0x13F85]="startstream", [0x13F94]="stonepowatleast", [0x14052]="setTYMTID",
    [0x140C0]="SmokeKnown", [0x1420A]="OtherPlayerInvisible", [0x1422D]="cameraoffon",
    [0x143B8]="brutalityoff", [0x144AD]="TYMWin", [0x14502]="spawnunlockext",
    [0x145ED]="fatalitytutor", [0x14606]="buttonthrough", [0x14624]="bgobjectlink",
    [0x146A1]="actionButton", [0x147F0]="audiostreamplay", [0x14967]="kitanaDone",
    [0x14985]="animstreamplay", [0x14999]="notindemo", [0x14AA7]="fistofruin",
    [0x14AD9]="forceloadstv", [0x14B24]="TYMFailID", [0x14BCE]="eventnotcomplete",
    [0x14D09]="kitanafree", [0x14DD1]="PhototLocked", [0x14E99]="spawnunlockable",
    [0x14EDA]="enabletether", [0x15024]="musicoverride", [0x15029]="ConcptArtLocked",
    [0x1512D]="randomtrigger", [0x152C7]="setspawncolor", [0x15574]="stonecolor",
    [0x1564B]="disablecontrol", [0x1568C]="breakcontainer", [0x156CD]="isoneplayer",
    [0x1570E]="notinstream", [0x15713]="DoBarakaMonkStr", [0x15826]="inair",
    [0x15BDC]="friendlyfire", [0x15FFB]="unlockmovie", [0x161CC]="unlockmap",
    [0x162DA]="cpycharstats", [0x16339]="unlockmk2", [0x163C0]="scorpion", [0x163F7]="inbossbattle",
    [0x16578]="finalvictory", [0x16659]="unlockartwork", [0x166B3]="fatalityover",
    [0x16735]="TYMFail", [0x16811]="audiostreambuffer", [0x16898]="VSresetpowerups",
    [0x168A2]="ArenaArtLocked", [0x168ED]="weaponspawnrndm", [0x16924]="play_cincamera",
    [0x16A00]="reaction", [0x16A4B]="eventcomplete", [0x16B9F]="unlockphotos",
    [0x16C1C]="finishhim", [0x16CAD]="spawnunlocknum", [0x1502E0]="gametext",
    [0x151130]="reverbenable", [0x153DC0]="applydamage", [0x158490]="blur",
    [0x15E150]="movetotrigger", [0x170290]="firetrigger", [0x170330]="activatetrigger",
    [0x170570]="pausetrigger", [0x17A010]="reactdirection", [0x17BA00]="modelstream",
    [0x17C580]="shake", [0x180CA0]="bodydamage", [0x18AAC0]="startanim", [0x192720]="aimesh",
    [0x194150]="aimeshlinks", [0x1941B0]="aimeshlinkid", [0x19A6F0]="move", [0x19A810]="rotate",
    [0x19AC20]="hitframe", [0x1A1510]="objectsound", [0x1A16D0]="objectsoundenable",
    [0x1A1720]="objectsounddisable", [0x1A1780]="soundeffect", [0x1A18F0]="vosound",
    [0x1A2530]="freezetime", [0x1A3350]="enemy_mutilate", [0x1A33A0]="enemy_resurrect",
    [0x1A33E0]="enemy_detach_bone", [0x1A3450]="mutilate_collision",
    [0x1A34A0]="enemy_detach_group", [0x1A3510]="inreaction", [0x1A3550]="notinreaction",
    [0x1A6D10]="visoverride", [0x1A8110]="streamanimdone", [0x1A8A10]="fogeffectreturn",
    [0x1A8C90]="fogeffect", [0x1A9980]="bgcharhide", [0x1A9C80]="bgchar", [0x1D22C0]="despawnall",
    [0x1D2300]="despchartype", [0x1D2710]="callspawn", [0x1D2740]="callspawnrc",
    [0x1D2780]="callspawnmerge", [0x1D68E0]="body_turn_event", [0x1DC4A0]="swapobject",
    [0x1DC520]="speedup", [0x1DE520]="cankill", [0x1DE590]="aionoff", [0x1DE600]="ndanim",
    [0x1DE670]="spwn_trig_pos", [0x1DE760]="setaito", [0x1DEA50]="stopneardeath",
    [0x1DEAC0]="startneardeath", [0x1DEB40]="setdefense", [0x1DEBC0]="setaidiff",
    [0x1E1210]="hidegroup", [0x1E3EC0]="lightning", [0x1E4950]="mat_state_set",
    [0x1E4A10]="mat_state_clear", [0x1F3CE0]="material", [0x1F3F10]="materialstate",
    [0x1F42E0]="object_quake",
}
-- MKSMK Probe plate tracer (diagnostics only, changes nothing).
-- Map triggers (manager [0x682020], records 0xD8 apart, count +0xA8C0) fire
-- when every condition command in their list passes: 0x16F4B0 walks
-- [rec+0x58] conditions, indices at [rec+0x5C], command objects at
-- mgr + index*24 + 0x11C00, each called as cmd(activator, def). 0x16F560 then
-- counts the pass (+0xCC; def+0x70 bit 17 needs more than def+0x79 passes)
-- and 0x16ED90 runs the trigger's events.
-- This tracer dumps every trigger whose conditions use a co-op/action
-- command, logs condition results when they change, and once the player
-- presses action on such a trigger it logs everything that follows. It
-- writes one report to the log when the game saves (probe_save.lua).
local TRIG_MGR_PTR  = 0x00682020
local TRIG_STRIDE   = 0xD8
local CHECK         = 0x0016F4B0
local TRY_FIRE      = 0x0016F560
local FIRE_EVENTS   = 0x0016ED90
local FRAME         = 0x005CE878
local GAME_MANAGER  = 0x005ACEBC
local STONE_POWER   = 0x00581B48
local ACTION_MASK   = 0x00582140
local MULTIPASS_BIT = 0x20000      -- def+0x70 flag: trigger needs more than one pass

local WATCH = { istwoplayer = true, isoneplayer = true, actionButton = true, buttonthrough = true,
    stonepowatleast = true, OtherPlayerInvisible = true, enabletether = true, isvs = true,
    stonecolor = true }
local COOP = { istwoplayer = true, isoneplayer = true }

local function ok(p)
    return p >= 0x10000 and (p < 0x7FFE0000 or (p >= 0x80000000 and p < 0x84000000)
        or (p >= 0xB0000000 and p < 0xC0000000) or (p >= 0xD0000000 and p < 0xE0000000)
        or (p >= 0xF0000000 and p < 0xF4000000))
end
local function hex(v) return string.format("%X", v) end
local function signed(v) if v >= 0x80000000 then return v - 0x100000000 end return v end

local seen = {}
local rec_count = {}
local dumped = {}
local stack = {}
local fire_stack = {}
local fires = {}
local armed_at = nil
local first_seen_at = nil
local arm_logged = {}
local multi = {}
local need_of = {}
local done = false

local RECORD_CAP   = 5            -- max entries per key before it goes quiet

-- Reported when the game saves (probe_save.lua). Entries go to the shared
-- head + tail log, so the start of the session and the activity just before
-- the save are both kept.
local function report(reason)
    done = true
    local manager = game.read_u32(GAME_MANAGER)
    local mode = ok(manager) and game.read_u32(manager + 0x88) or -1
    error("PLATE " .. reason .. " mode=" .. mode .. " n=" .. log_count()
        .. " stone=" .. game.read_u32(STONE_POWER)
        .. " mask=" .. hex(game.read_u32(ACTION_MASK)) .. " | " .. log_text(), 0)
end

local record = log_add

-- Record a change, but cap how many times one key can speak so an ambient
-- trigger firing every frame cannot eat the whole budget. The last allowed
-- entry for a key is suffixed "~" to show it was then silenced.
local function emit(key, text)
    local n = rec_count[key] or 0
    if n >= RECORD_CAP then
        return
    end
    rec_count[key] = n + 1
    record(n + 1 == RECORD_CAP and (text .. "~") or text)
end

-- Log only when the value for this key changes.
local function changed(key, text)
    if seen[key] == text then
        return
    end
    seen[key] = text
    emit(key, text)
end

-- Log a change and report whether this is a transition (not first sight).
local function note(key, text)
    local prev = seen[key]
    seen[key] = text
    if prev == text then return false end
    emit(key, text)
    return prev ~= nil
end

-- Start the report window. The FIRST player-driven disturbance wins and is
-- never overwritten, so ambient triggers firing every frame cannot keep
-- pushing the timeout out forever (which would suppress the report entirely).
local function arm(index, tag)
    if armed_at == nil then
        armed_at = game.read_u32(FRAME)
    end
    local key = tag .. (index or "")
    if not arm_logged[key] then
        arm_logged[key] = true
        record(tag .. (index or ""))
    end
end

local function timers()
end

local function manager()
    local mgr = game.read_u32(TRIG_MGR_PTR)
    if not ok(mgr) then return nil end
    return mgr
end

local function trigger_index(mgr, rec)
    if rec < mgr or (rec - mgr) % TRIG_STRIDE ~= 0 then return nil end
    local index = (rec - mgr) // TRIG_STRIDE
    if index >= game.read_u32(mgr + 0xA8C0) then return nil end
    return index
end

local function command_name(mgr, slot)
    if slot > game.read_u32(mgr + 0x1254C) then return "?" .. slot end
    local object = game.read_u32(mgr + slot * 24 + 0x11C00)
    if not ok(object) then return "?" .. slot end
    local vtable = game.read_u32(object)
    if not ok(vtable) then return "?" .. slot end
    local execute = game.read_u32(vtable)
    return NAMES[execute] or hex(execute)
end

-- 0 = not interesting, 1 = action/stone trigger, 2 = co-op trigger
local function classify(mgr, rec, index)
    local known = dumped[index]
    if known ~= nil then return known end
    local count = game.read_u32(rec + 0x58)
    local slots = game.read_u32(rec + 0x5C)
    local args = game.read_u32(rec + 0x60)
    local level, names = 0, {}
    if count > 0 and count <= 12 and ok(slots) then
        for j = 0, count - 1 do
            local name = command_name(mgr, game.read_u32(slots + j * 4))
            if WATCH[name] then level = math.max(level, 1) end
            if COOP[name] then level = 2 end
            local arg = ok(args) and game.read_u32(args + j * 4) or 0
            names[#names + 1] = arg ~= 0 and (name .. ":" .. hex(arg)) or name
        end
    end
    dumped[index] = level
    local def = game.read_u32(rec + 0xC)
    local flags = ok(def) and game.read_u32(def + 0x70) or 0
    local need = ok(def) and game.read_u8(def + 0x79) or 0
    multi[index] = (flags & MULTIPASS_BIT) ~= 0 and need >= 2
    need_of[index] = need
    -- A multi-pass trigger is a co-op gate even if its conditions look plain,
    -- so treat it as interesting regardless of the command names.
    if multi[index] and level < 1 then level = 1 end
    dumped[index] = level
    if level > 0 then
        if first_seen_at == nil then
            first_seen_at = game.read_u32(FRAME)
        end
        record("T" .. index .. "{f" .. hex(flags) .. ",n" .. need .. ",c" .. game.read_u32(rec + 0xCC)
            .. (multi[index] and ",M" or "") .. "}" .. table.concat(names, ","))
    end
    return level
end

local function activator(address)
    local ref = game.read_u32(address)
    if not ok(ref) then return "-" end
    return tostring(signed(game.read_u32(ref + 0x10)))
end

local hooks = {
    {
        address = SAVE_GAME,
        before = function(ctx)
            if save_due() and not done and log_count() > 0 then report(save_tag("save")) end
        end,
    },
    {
        address = CHECK,
        before = function(ctx)
            if done then return end
            local mgr = manager()
            local index = mgr and trigger_index(mgr, ctx.ecx)
            local level = index and classify(mgr, ctx.ecx, index) or 0
            stack[#stack + 1] = { index = index, level = level, who = level > 0 and activator(ctx.esp + 4) or "" }
        end,
        after = function(ctx)
            if done then return end
            local top = table.remove(stack)
            if top and top.level > 0 then
                local key = "t" .. top.index .. "@" .. top.who
                -- Record every transition, but only a co-op (level 2) trigger
                -- opens the report window: ambient triggers change state on
                -- their own and must not start (or hold open) the capture.
                if note(key, key .. "=" .. (ctx.eax & 0xFF)) and top.level == 2 then
                    arm(top.index, "ARMC")
                end
            end
            timers()
        end,
    },
    {
        address = TRY_FIRE,
        before = function(ctx)
            fire_stack[#fire_stack + 1] = ctx.ecx
        end,
        after = function(ctx)
            local rec = table.remove(fire_stack)
            if done or rec == nil then return end
            local mgr = manager()
            local index = mgr and trigger_index(mgr, rec)
            if index and (multi[index] or (dumped[index] or 0) > 0 or armed_at) then
                local passes = game.read_u32(rec + 0xCC)
                -- Record the pass counter and fires (both capped) but never arm
                -- here: ambient multi-pass triggers step every frame, and arming
                -- on them is what flooded the old report and suppressed the dump.
                if multi[index] then
                    note("P" .. index, "P" .. index .. "c" .. passes .. "/" .. (need_of[index] or 0))
                end
                if (ctx.eax & 0xFF) ~= 0 then
                    note("F" .. index, "F" .. index .. "c" .. passes)
                end
            end
            timers()
        end,
    },
    {
        address = FIRE_EVENTS,
        before = function(ctx)
            if done then return end
            local mgr = manager()
            local index = mgr and trigger_index(mgr, ctx.ecx - 0x68)
            if index and ((dumped[index] or 0) > 0 or armed_at) then
                local who = activator(ctx.esp + 4)
                local count = (fires[index] or 0) + 1
                fires[index] = count
                if count <= 3 or count % 60 == 0 then record("E" .. index .. "@" .. who .. "#" .. count) end
            end
        end,
    },
}

local pending = {}
for execute, name in pairs(NAMES) do
    hooks[#hooks + 1] = {
        address = execute,
        before = function(ctx)
            if done then return end
            local top = stack[#stack]
            if armed_at or (top and top.level > 0) then
                pending[name] = activator(ctx.esp + 4)
            end
        end,
        after = function(ctx)
            if done then return end
            local who = pending[name]
            if who == nil then return end
            pending[name] = nil
            local top = stack[#stack]
            local result = ctx.eax & 0xFF
            local where = top and top.index and ("" .. top.index) or "-"
            changed(where .. name .. who, name .. "(" .. who .. ")" .. "=" .. result .. "/T" .. where)
            if name == "actionButton" and result == 1 and top and top.level > 0 then
                arm(top.index, "ARMB")
            end
        end,
    }
end
return hooks
