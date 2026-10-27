local LOADMAP       = 0x00012883
local FIRE_EVENTS   = 0x0016ED90
local CURRENT_MAP   = 0x00505970
local TRIG_MGR_PTR  = 0x00682020
local TRIG_STRIDE   = 0xD8
local PORTAL_TRIGGER = 27
local RIFT_AREAS = {
    [1] = true,       -- Wu Shi
    [100] = true,     -- Goro's Lair: authored boss and enemy groups
}

local portal_event = false

local hooks = {
    {
        address = FIRE_EVENTS,
        before = function(ctx)
            local mgr = game.read_u32(TRIG_MGR_PTR)
            portal_event = RIFT_AREAS[game.read_u32(CURRENT_MAP)] == true
                and ctx.ecx - 0x68 == mgr + PORTAL_TRIGGER * TRIG_STRIDE
        end,
        after = function()
            portal_event = false
        end,
    },
    {
        address = LOADMAP,
        before = function(ctx)
            if not portal_event then return end
            local def = game.read_u32(ctx.esp + 4)
            local args = game.read_u32(def + 8)
            game.write_u32(args, game.read_u32(CURRENT_MAP) + 1)
            game.write_u32(args + 4, 0)
        end,
    },
}

return hooks
