-- Pause Save: Back pressed fresh on the main pause page sets the menu
-- manager's save-after byte and closes the pause menu, once; nothing happens
-- outside the pause menu, on a sub-page, or while Back is still held from
-- before the pause.
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local m = H.load(arg[1])
local PAUSE, PAUSE_TWIN, FRAME = 0x00012BA8, 0x00015722, 0x000142EB
local MGR, PAGE, PADS = 0x004EF3C8, 0x0059E364, 0x0063ABC8
local CTX = { ecx = MGR, esp = 0xD00F0000 }
local function back(port, down) H.w16(PADS + port * 0x16 + 4, down and 0x20 or 0) end
local function frame() H.invoke(m, FRAME, CTX, nil) end
local function reset() H.w8(MGR + 0x693, 0); H.w8(MGR + 0x64, 0) end
local function asked() return H.r8(MGR + 0x693) == 1 and H.r8(MGR + 0x64) == 1 end

H.w32(PAGE, 3); H.w32(MGR + 0x54, 3)

-- outside the pause menu (statue save menu, debug menus): untouched
back(0, true); frame(); back(0, false); frame(); back(0, true); frame()
assert(not asked(), "Back outside the pause menu must do nothing")
back(0, false)

-- pause, press Back: the save menu is asked for, once
H.invoke(m, PAUSE, CTX, function()
  frame(); frame()
  assert(not asked(), "no request before Back")
  back(0, true); frame()
  assert(asked(), "Back on the pause page asks for the save menu")
  reset(); back(0, false); frame(); back(0, true); frame()
  assert(not asked(), "only one request per pause (the save menu runs inside it)")
end)
back(0, false); reset()

-- Back held while pausing: needs a release first
back(0, true)
H.invoke(m, PAUSE_TWIN, CTX, function()
  frame(); frame()
  assert(not asked(), "Back held from before the pause must not trigger")
  back(0, false); frame(); back(0, true); frame()
  assert(asked(), "fresh press after release triggers (twin pause menu)")
end)
back(0, false); reset()

-- sub-page (options): untouched; player 2's pad works on the main page
H.invoke(m, PAUSE, CTX, function()
  H.w32(MGR + 0x54, 5)
  frame(); back(1, true); frame()
  assert(not asked(), "Back on a pause sub-page must do nothing")
  back(1, false); frame()
  H.w32(MGR + 0x54, 3)
  back(1, true); frame()
  assert(asked(), "player 2 pad triggers on the main pause page")
end)
back(1, false); reset()

-- after the pause menu returned: untouched again
back(0, true); frame(); back(0, false); frame(); back(0, true); frame()
assert(not asked(), "Back after the pause menu closed must do nothing")

assert(#H.failed == 0, "script error: " .. tostring(H.failed[1]))
print("max_writes", H.max_writes, "max_instr", H.max_instr)
print("PASS pause_save")
