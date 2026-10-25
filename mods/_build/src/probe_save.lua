-- ===== MKSMK Probe save-triggered reporting (shared by every probe script) =====
-- A routine script can only write to the game log by failing with an error,
-- and that also disables it for the rest of the session: one report per
-- script per session. So each probe collects quietly and writes its report
-- when the game saves. Every save ends in 0x1272A0, the HardDisk write: it
-- creates the save container (SaveMeta.xbx) and opens save.dat with
-- GENERIC_WRITE. (0x127420 is the matching read; 0.8.0 hooked 0xA2260, a
-- save path the statue does not use.) Play, test, save at a statue, quit.
-- A script with nothing collected yet waits for the next save. The log keeps
-- the first LOG_HEAD and the last LOG_TAIL entries plus a count of the ones
-- dropped in between, so a long session stays bounded.
local SAVE_GAME  = 0x001272A0
local SAVE_INDEX = 1          -- this copy reports at the SAVE_INDEX-th save (build.py makes copies)
local LOG_HEAD   = 100
local LOG_TAIL   = 400

-- 0.10: a script still reports only once, so build.py ships copies with
-- SAVE_INDEX 1, 2 and 3. Each copy reports at that save of the session (or the
-- next save after it, if it had nothing yet) and holds everything since the
-- game started.
local saves_seen = 0
local function save_due()
    saves_seen = saves_seen + 1
    return saves_seen >= SAVE_INDEX
end
local function save_tag(reason)
    return reason .. "#" .. SAVE_INDEX
end

local log_head, log_ring = {}, {}
local log_ring_n, log_ring_at, log_total = 0, 0, 0

local function log_add(text)
    log_total = log_total + 1
    if #log_head < LOG_HEAD then
        log_head[#log_head + 1] = text
        return
    end
    log_ring_at = log_ring_at % LOG_TAIL + 1
    log_ring[log_ring_at] = text
    if log_ring_n < LOG_TAIL then log_ring_n = log_ring_n + 1 end
end

local function log_count()
    return log_total
end

local function log_text()
    local out = {}
    for i = 1, #log_head do out[#out + 1] = log_head[i] end
    local dropped = log_total - #log_head - log_ring_n
    if dropped > 0 then out[#out + 1] = "...(" .. dropped .. " dropped)..." end
    local start = log_ring_n < LOG_TAIL and 1 or (log_ring_at % LOG_TAIL + 1)
    for k = 0, log_ring_n - 1 do
        out[#out + 1] = log_ring[(start - 1 + k) % LOG_TAIL + 1]
    end
    return table.concat(out, " ")
end
