-- ===== callgate v1: make the game call one of its own routines =====
-- Routine scripts can only read and write memory, but the Recomp resolves
-- indirect calls through its table of recompiled routines, so pointing a
-- virtual call at another routine is a guest call (callgate_test 0.1.1).
--
-- The gate: every frame 0xC74E0 calls thunk 0x12284 (from 0xC7529 only), then
-- the getter 0x11131 (singleton 0x5892A8), then the singleton's vtable slot
-- +0x18 (0x36B40: thiscall, no stack arguments) at 0xC7537, then thunk
-- 0x12C93. Arming, in 0x12284's after hook, writes the target into a word
-- below esp (only the getter's return address lands under esp before the
-- call) and points the singleton's vtable so slot +0x18 reads that word. The
-- target's before hook puts the vtable back, so 0x36B40 skips one frame per
-- call.
--
-- In the target's before hook the gate builds a fresh frame below the entry
-- esp (return address, arguments, then the data blocks and strings they
-- point to) and moves esp there, so the caller's stack is never written. The
-- after hook sets esp to entry + 4, where the gate's no-argument call
-- expects it, however many bytes the callee popped.
--
-- Usage; every target must be a routine in the Recomp's function table (a
-- jmp thunk is one, the body it jumps to is not): check addresses with
-- tools/recomp/funcs.py before shipping.
--   callgate.target(0x11938)                       -- before callgate.hooks
--   callgate.call(0x11938, {
--       args = { callgate.block{ 0, 0, callgate.block{ 25 } }, 0, 0 },
--       ecx = nil, regs = nil,                     -- optional register values
--       done = function(eax, popped) end })        -- eax nil: the call never ran
--   return callgate.hooks(hooks)
-- One call runs per frame, in queue order, and one script's call per frame
-- across all mods (arming needs the vanilla vtable). Blocks and strings live
-- on the stack for the duration of the call only. Don't hook a target
-- address in the script's own hooks too. done runs from the gate's next hook
-- (0x12C93, the same frame), never from the target's hooks: routine Lua has no
-- pcall, and a failing callback drops its writes, esp included.
local callgate = (function()
    local GATE_PRE  = 0x00012284
    local GATE_POST = 0x00012C93
    local GATE_RET  = 0x000C753A    -- return address of the gate call
    local INSTANCE  = 0x00589270
    local SINGLETON = 0x005892A8
    local VTABLE    = 0x00497C60
    local SLOT      = 0x18
    local FAKE_SLOT = 0x40          -- below esp at the arming point
    local FRAME_GAP = 0x40          -- between the new frame's data and the entry esp

    local M = {}
    local targets, queue = {}, {}
    local active        -- the call in flight: "armed", then "called"
    local finished      -- { call, eax, popped } waiting for its done callback

    function M.target(address)
        targets[address] = true
    end

    function M.block(words)
        return { block = words }
    end

    function M.pending()
        return #queue + (active and 1 or 0) + (finished and 1 or 0)
    end

    function M.call(address, opts)
        if not targets[address] then
            error(string.format("callgate: %08X was not declared with callgate.target", address), 2)
        end
        queue[#queue + 1] = { address = address, opts = opts or {} }
    end

    -- bytes a value needs in the frame's data area, its nested blocks included
    local function data_size(v)
        if type(v) == "string" then
            return (#v + 4) & ~3
        elseif type(v) == "table" then
            local n = #v.block * 4
            for _, w in ipairs(v.block) do
                n = n + data_size(w)
            end
            return n
        end
        return 0
    end

    -- writes v's data at cursor; returns the word that stands for v and the
    -- next free address
    local function place(v, cursor)
        if type(v) == "number" then
            return v & 0xFFFFFFFF, cursor
        end
        local at = cursor
        if type(v) == "string" then
            local padded = v .. string.rep("\0", ((#v + 4) & ~3) - #v)
            -- string arguments are untested in game (string.byte is not in the
            -- runtime's removed-function list; nothing shipped uses it yet)
            for i = 1, #padded, 4 do
                local b1, b2, b3, b4 = string.byte(padded, i, i + 3)
                game.write_u32(at + i - 1, b1 | (b2 << 8) | (b3 << 16) | (b4 << 24))
            end
            return at, at + #padded
        end
        local words = v.block
        cursor = at + #words * 4
        for i, w in ipairs(words) do
            local word
            word, cursor = place(w, cursor)
            game.write_u32(at + (i - 1) * 4, word)
        end
        return at, cursor
    end

    local function arm(ctx)
        if active or finished or #queue == 0 then
            return
        end
        if game.read_u32(INSTANCE) ~= SINGLETON or game.read_u32(SINGLETON) ~= VTABLE then
            return
        end
        local call = table.remove(queue, 1)
        local slot = ctx.esp - FAKE_SLOT
        game.write_u32(slot, call.address)
        game.write_u32(SINGLETON, slot - SLOT)
        call.state = "armed"
        active = call
    end

    local function enter(ctx, address)
        local call = active
        if not call or call.state ~= "armed" or call.address ~= address
            or ctx.ecx ~= SINGLETON or game.read_u32(ctx.esp) ~= GATE_RET then
            return
        end
        game.write_u32(SINGLETON, VTABLE)
        local opts, entry = call.opts, ctx.esp
        local args = opts.args or {}
        local frame = entry
        if #args > 0 then
            local size = 0
            for _, a in ipairs(args) do
                size = size + data_size(a)
            end
            frame = entry - FRAME_GAP - size - 4 * (#args + 1)
            frame = frame - ((frame - entry) & 0xF)     -- keep entry's 16-byte alignment
            game.write_u32(frame, GATE_RET)
            local cursor = frame + 4 + 4 * #args
            for i, a in ipairs(args) do
                local word
                word, cursor = place(a, cursor)
                game.write_u32(frame + 4 * i, word)
            end
            ctx.esp = frame
        end
        if opts.ecx then
            ctx.ecx = opts.ecx
        end
        for name, value in pairs(opts.regs or {}) do
            ctx[name] = value
        end
        call.entry, call.frame, call.state = entry, frame, "called"
    end

    local function leave(ctx, address)
        local call = active
        -- a nested call of the same routine returns below our frame
        if not call or call.state ~= "called" or call.address ~= address or ctx.esp < call.frame + 4 then
            return
        end
        local popped = ctx.esp - call.frame - 4
        ctx.esp = call.entry + 4
        active = nil
        finished = { call = call, eax = ctx.eax, popped = popped }
    end

    local function post(ctx)
        local call = active
        if call and call.state == "armed" then
            -- the target never ran: put the vtable back now, report next frame
            game.write_u32(SINGLETON, VTABLE)
            active = nil
            finished = { call = call }
            return
        elseif call and call.state == "called" then
            active = nil
            error(string.format("callgate: %08X returned without its after hook", call.address), 0)
        end
        local done = finished
        if done then
            finished = nil
            if done.call.opts.done then
                done.call.opts.done(done.eax, done.popped)
            end
        end
    end

    function M.hooks(hooks)
        hooks[#hooks + 1] = { address = GATE_PRE, after = arm }
        hooks[#hooks + 1] = { address = GATE_POST, before = post }
        for address in pairs(targets) do
            hooks[#hooks + 1] = {
                address = address,
                before = function(ctx) enter(ctx, address) end,
                after = function(ctx) leave(ctx, address) end,
            }
        end
        return hooks
    end

    return M
end)()
