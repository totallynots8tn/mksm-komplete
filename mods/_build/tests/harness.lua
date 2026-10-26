-- Minimal emulation of the Recomp routine runtime for offline tests.
local H = {}
local mem = {}
H.mem = mem
-- committed guest regions (image, physical RAM window, one stack area)
local REGIONS = { {0x10000, 0x8C2000}, {0x80000000, 0x84000000}, {0xD0000000, 0xD0100000} }
local function committed(a, n)
  for _, r in ipairs(REGIONS) do if a >= r[1] and a + n <= r[2] then return true end end
  return false
end
local staged = nil
local writes = 0
H.max_writes = 0
H.max_instr = 0

local in_api = false
local function rd(a, n)
  in_api = true
  if not committed(a, n) then error("Guest memory read is outside committed memory "..string.format("%x",a)) end
  local v = 0
  for i = n-1, 0, -1 do
    local b = mem[a+i] or 0
    if staged then for _, w in ipairs(staged) do if a+i >= w.a and a+i < w.a + w.n then b = (w.v >> (8*(a+i-w.a))) & 0xFF end end end
    v = (v << 8) | b
  end
  in_api = false
  return v
end
local function wr(a, v, n)
  in_api = true
  if math.type(v) ~= "integer" or v < 0 or v > 0xFFFFFFFF then error("Expected an unsigned 32-bit value") end
  if n < 4 and v >= (1 << (8*n)) then error("Value exceeds the selected memory width") end
  if not committed(a, n) then error("Guest memory write is outside committed memory "..string.format("%x",a)) end
  writes = writes + 1
  if writes > 256 then error("Routine memory write budget exceeded") end
  staged[#staged+1] = {a=a, v=v, n=n}
  in_api = false
end
-- single-precision values, as the runtime's game.read_f32 / game.write_f32
-- (routines.cpp): the same bytes as a u32, staged like any other write
local function f32_bits(f)
  if type(f) ~= "number" then error("Expected a number") end
  return (string.unpack("<I4", string.pack("<f", f)))
end
H.game = {
  read_u8=function(a) return rd(a,1) end, read_u16=function(a) return rd(a,2) end, read_u32=function(a) return rd(a,4) end,
  write_u8=function(a,v) wr(a,v,1) end, write_u16=function(a,v) wr(a,v,2) end, write_u32=function(a,v) wr(a,v,4) end,
  read_f32=function(a) return (string.unpack("<f", string.pack("<I4", rd(a,4)))) end,
  write_f32=function(a,f) wr(a, f32_bits(f), 4) end,
}
function H.rf32(a) return (string.unpack("<f", string.pack("<I4", H.r32(a)))) end
function H.wf32(a,f) H.w32(a, f32_bits(f)) end
-- direct (game-side) memory access
function H.r(a,n) local v=0 for i=n-1,0,-1 do v=(v<<8)|(mem[a+i] or 0) end return v end
function H.w(a,v,n) for i=0,n-1 do mem[a+i]=(v>>(8*i))&0xFF end end
function H.r32(a) return H.r(a,4) end function H.w32(a,v) H.w(a,v,4) end
function H.r16(a) return H.r(a,2) end function H.w16(a,v) H.w(a,v,2) end
function H.w8(a,v) H.w(a,v,1) end function H.r8(a) return H.r(a,1) end

-- The game's Lua 5.4 has only the standard math library: no frexp, ldexp,
-- pow, cosh, sinh, tanh, log10 (the compat functions lupa may still carry).
local STRICT_MATH = {}
for _, k in ipairs({ "abs", "acos", "asin", "atan", "ceil", "cos", "deg", "exp", "floor", "fmod",
                     "huge", "log", "max", "maxinteger", "min", "mininteger", "modf", "pi", "rad",
                     "random", "randomseed", "sin", "sqrt", "tan", "tointeger", "type", "ult" }) do
  STRICT_MATH[k] = math[k]
end
function H.load(path)
  local env = setmetatable({game=H.game, math=STRICT_MATH}, {__index=_G})
  env.print=nil env.pcall=nil env.xpcall=nil env.load=nil env.dofile=nil env.loadfile=nil env.setmetatable=nil env.getmetatable=nil
  local f = assert(loadfile(path, "t", env))
  local hooks = f()
  local by = {}
  for _, h in ipairs(hooks) do by[h.address] = by[h.address] or {} ; table.insert(by[h.address], h) end
  return by
end
H.failed = {}
local function call(fn, ctx)
  staged = {}; writes = 0
  local count = 0
  debug.sethook(function() if not in_api then count = count + 1; if count > 100000 then error("Routine instruction budget exceeded") end end end, "", 1)
  local ok, err = pcall(fn, ctx)
  debug.sethook()
  if writes > H.max_writes then H.max_writes = writes end
  if count > H.max_instr then H.max_instr = count end
  if not ok then H.failed[#H.failed+1] = err; staged = nil; return false end
  for _, w in ipairs(staged) do H.w(w.a, w.v, w.n) end
  staged = nil
  return true
end
-- invoke(by, address, ctx, original) : before hooks, original, after hooks
function H.invoke(by, address, ctx, original)
  local list = by[address] or {}
  for _, h in ipairs(list) do if h.before then call(h.before, ctx) end end
  if original then original(ctx) end
  for _, h in ipairs(list) do if h.after then call(h.after, ctx) end end
end
return H
