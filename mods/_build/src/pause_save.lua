-- ===== Pause Save 0.9 (save from the pause menu, for soft-lock recovery) =====
-- SHELVED 2026-10-24: in the game, pause + Back did nothing. The log shows
-- Back (0x0020) reaching the input buffer and no script error, so the hooks
-- never matched. Either the pause seen in play isn't 0xA4810/0xA4670, or the
-- page-handle check fails. Not in build.py; package moved to
-- mods/_shelved/pause_save. To revisit, first probe calls to the thunks
-- 0x12BA8, 0x15722 and 0x142EB while pausing.
-- A soft-lock that needs Alt+F4 loses everything since the last save statue.
-- Pause Save opens the statue's own save menu from the pause menu: pause,
-- then press Back (Backspace on the keyboard, View/Share on a pad). Pick a
-- slot and save as usual; the game resumes when the save menu closes.
--
-- How it works: the pause menu (0xA4810, entered through thunk 0x12BA8;
-- 0xA4670 through 0x15722 is its twin) runs menu frames through 0x93D40
-- (thunk 0x142EB) until the menu manager's closed byte [mgr+0x64] is set.
-- After it closes it checks [mgr+0x693] and, when set, calls OpenSaveMenu
-- (0xA2300), the routine a save statue's trigger event calls (0xA54D0). No
-- shipped pause item sets 0x693, so the save option was cut. This mod sets
-- it and closes the pause menu when Back is pressed on the main pause page.
local PAUSE_MENUS  = { 0x00012BA8, 0x00015722 }
local MENU_FRAME   = 0x000142EB   -- 0x93D40: one frame of the in-game menu loop
local PAUSE_PAGE   = 0x0059E364   -- handle of the open pause page
local MENU_CURRENT = 0x54         -- menu manager: current page handle
local MENU_CLOSED  = 0x64         -- menu manager: set to end the menu loop
local SAVE_AFTER   = 0x693        -- menu manager: open the save menu once the pause menu closes
local PADS         = 0x0063ABC8   -- XINPUT_STATE per port: packet number, then wButtons
local PAD_STRIDE   = 0x16
local PAD_BUTTONS  = 4
local PAD_PORTS    = 4
local BACK         = 0x0020

local paused = 0             -- pause menus running (the save menu runs inside one)
local back_held = true       -- Back must be pressed fresh inside the pause menu
local requested = false

local function back_down()
    for port = 0, PAD_PORTS - 1 do
        if (game.read_u16(PADS + port * PAD_STRIDE + PAD_BUTTONS) & BACK) ~= 0 then
            return true
        end
    end
    return false
end

local hooks = {}

for _, address in ipairs(PAUSE_MENUS) do
    hooks[#hooks + 1] = {
        address = address,
        before = function(ctx)
            paused = paused + 1
            back_held = true
            requested = false
        end,
        after = function(ctx)
            if paused > 0 then
                paused = paused - 1
            end
        end,
    }
end

hooks[#hooks + 1] = {
    address = MENU_FRAME,
    before = function(ctx)
        if paused == 0 or requested then
            return
        end
        local manager = ctx.ecx
        local down = back_down()
        if down and not back_held
            and game.read_u32(manager + MENU_CURRENT) == game.read_u32(PAUSE_PAGE) then
            game.write_u8(manager + SAVE_AFTER, 1)
            game.write_u8(manager + MENU_CLOSED, 1)
            requested = true
        end
        back_held = down
    end,
}

return hooks
