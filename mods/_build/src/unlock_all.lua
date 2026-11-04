local BITSET = 0x005A375C

local function read(address)
    return game.read_u32(address)
end

local function set_range(words, first, last)
    for bit = first, last do
        local word = bit // 32
        words[word] = words[word] | (1 << (bit % 32))
    end
end

local function apply()
    local words = {}
    for i = 0, 12 do
        words[i] = read(BITSET + i * 4)
    end

    -- The game's routine uses three chunks and skips bits 165 and 342.
    set_range(words, 101, 164)
    set_range(words, 166, 341)
    set_range(words, 343, 358)

    -- Same extra masks as the game's own full-unlock routine.
    words[2] = words[2]
        | read(0x004FC390) | read(0x004FC394) | read(0x004FC398)
        | read(0x004FC3A8) | read(0x004FC3AC) | read(0x004FC3B0)
        | read(0x004FC3B8) | read(0x004FC3BC) | read(0x004FC3C0)
        | read(0x004FC3C4)

    words[3] = words[3]
        | read(0x004FC348) | read(0x004FC34C) | read(0x004FC350) | read(0x004FC354)

    words[11] = words[11]
        | read(0x004FC380) | read(0x004FC384) | read(0x004FC388)
        | read(0x004FC38C) | read(0x004FC390) | read(0x004FC394)
        | read(0x004FC398) | read(0x004FC39C) | read(0x004FC3A0)

    -- Bytes 0x5A378D/8E/8F are exact-value flags, not bit fields.
    words[12] = (words[12] & 0xFF) | 0x01010100

    for i = 0, 12 do
        game.write_u32(BITSET + i * 4, words[i])
    end
end

local function applied()
    return (read(BITSET + 8) & 0xF71C0000) == 0xF71C0000
       and (read(BITSET + 12) & 0xFFFFFFEF) == 0xFFFFFFEF
       and (read(BITSET + 44) & 0x007FC07F) == 0x007FC07F
       and (read(BITSET + 48) & 0xFFFFFF00) == 0x01010100
end

local function ensure()
    if not applied() then
        apply()
    end
end

return {
    -- Profile load: reapply after the profile's bitset is copied into memory.
    { address = 0x00014D36, after = function(ctx) apply() end },

    -- Character-select list build: make sure the roster bits are present first.
    { address = 0x000127BB, before = function(ctx) ensure() end },

    -- Game/menu mode getter: cheap safety net after new-profile resets.
    { address = 0x000138F0, before = function(ctx) ensure() end },
}
