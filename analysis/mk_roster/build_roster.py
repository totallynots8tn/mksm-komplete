"""Rebuild the Shaolin Monks character roster from the game files.

Writes roster.csv, roster.json and roster.lua next to this script, one row per
character type (0-90). A type is a row of the character table at 0x4FA9F0:
the number in spawn entries (+0x00), map preload lists, LOADED_TYPES, the
modelstream command and entity +0x1DFE.

Reads default.xbe (analysis/xbe_lib.py) and GAMEDATA.WAD from the redump ISO
(analysis/xbox_roster/tools/pwf.py, path in xiso.py), plus the shared boss and
outsider lists in mods/_build/src/core.lua and the Time Rifts bosses, so the
table says which mods treat each type how. Names, roles and evidence that the
files can't give are in CURATED below (see README.md for the sources).

    python analysis/mk_roster/build_roster.py
"""
import csv
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(HERE, '..'))
sys.path.insert(0, os.path.join(HERE, '..', 'xbox_roster', 'tools'))
from xbe_lib import x  # noqa: E402
import pwf  # noqa: E402

CHAR_TABLE, CHAR_ROW = 0x4FA9F0, 0x30       # 91 rows; +0x00 = 0x20004 + type
SOUND_TABLE, SOUND_ROW = 0x4F9EA0, 0x20     # bank, sound font, voice archive, flag
MAP_TABLE = 0x5020E8                        # map id -> descriptor
DEBUG_MENU = 0x4E6078                       # (label, map) pairs of the dev menu
WAD_SHIFT = 0x14                            # engine file id F = pwf.py record F - 0x14
AI_SETUP_JUMP = 0xE2F1D                     # per-character AI setup: jmp [eax*4 + table], eax = type - 2
AI_SETUP_TABLE, AI_SETUP_CASES = 0xE8CE8, 0x55
TYPES = 91
NONE = 0xFFFFFFFF

# Curated knowledge: name, role, evidence. Roles: player (story and versus),
# playable (unlockable story/versus fighter), versus (versus-only model),
# mk (Mortal Kombat character used as an NPC or boss), boss (critical-path
# giant), enemy (regular grunt or creature), unknown.
CURATED = {
    0: ('Liu Kang', 'player', 'P1 by default; move menu root 0'),
    1: ('Kung Lao', 'player', 'P2 by default; move menu root 1'),
    4: ('clay soldier?', 'enemy', ''),
    7: ('swordsman', 'enemy', ''),
    8: ('corpse', 'enemy', ''),
    10: ('captain', 'enemy', 'Shaolin Shuffle outsider'),
    11: ('general (naginata)', 'enemy', 'Shaolin Shuffle outsider'),
    12: ('archer', 'enemy', 'Shaolin Shuffle outsider'),
    13: ('handler', 'enemy', 'Shaolin Shuffle outsider'),
    14: ('Tarkatan', 'enemy', 'the most common grunt: preloaded by most early maps'),
    15: ('Oni', 'enemy', 'model "dokaebi"'),
    18: ('corpse', 'enemy', ''),
    19: ('knight', 'enemy', 'sound bank "...lem_knight"'),
    20: ('masked humanoid', 'enemy', ''),
    25: ('katana humanoid', 'enemy', ''),
    26: ('mask guard', 'enemy', ''),
    27: ('priest', 'enemy', ''),
    28: ('bladed humanoid', 'unknown', 'instances 2 like the bosses; core.lua listed it as an Orochi (names were two off)'),
    30: ('Orochi', 'boss', 'model "orochi", sound "hellbeast"; Time Rifts 0.6.0 QA: dropped in map 110, fought, beaten'),
    31: ('Shokan', 'enemy', ''),
    34: ('archer (quiver)', 'enemy', 'core.lua lists it as a boss (it was thought to be a club warlord)'),
    35: ('archer (quiver)', 'enemy', ''),
    36: ('Oni Warlord', 'boss', 'model "warlord" + club; Time Rifts 0.5.7 QA: dropped in map 110, leapt the fence'),
    40: ('winged creature', 'enemy', ''),
    41: ('winged creature', 'enemy', ''),
    42: ('tree mouth', 'enemy', 'Living Forest; Shaolin Shuffle outsider'),
    43: ('tree arms', 'enemy', 'Living Forest; Shaolin Shuffle outsider'),
    44: ('bat', 'enemy', ''),
    45: ('swamp snake', 'enemy', ''),
    46: ('skull', 'enemy', 'instances 66: a swarm'),
    47: ('Goro (mace)', 'boss', 'one of the only two 2-slot types'),
    48: ('tentacles', 'enemy', ''),
    49: ('dagger creature', 'enemy', ''),
    50: ('big snake', 'enemy', 'map 144 (Reptile battle) preloads it'),
    52: ('Scorpion', 'mk', 'NPC/boss model; map 160 (Scorpion battle) preloads it'),
    53: ('Noob Saibot', 'mk', 'no sound bank or animation record of its own (ninja skeleton like Scorpion and Smoke)'),
    54: ('Kano', 'mk', ''),
    55: ('Scorpion (burned)', 'mk', 'map 160 (Scorpion battle) preloads it'),
    56: ('Baraka', 'mk', 'map 15 (Baraka battle) preloads it'),
    57: ('Goro', 'boss', '2 slots; map 47 (Goro battle) preloads it'),
    58: ('Kintaro', 'boss', ''),
    59: ('Reptile', 'mk', 'map 144 (Reptile battle) preloads it; LDK v1 cloned it into waves (patch 4)'),
    60: ('unnamed humanoid', 'unknown', 'next to Shang Tsung in the table'),
    61: ('unnamed humanoid', 'unknown', 'next to Shang Tsung in the table'),
    62: ('Shang Tsung (young)', 'mk', 'map 73 (final battle) preloads it'),
    63: ('Shang Tsung (old)', 'mk', ''),
    64: ('Shao Kahn', 'boss', 'map 73 (final battle) preloads it; Time Rifts 0.7.x dropped it as "Mileena" (removed: 62,000 units from P1)'),
    65: ('Kitana', 'mk', 'map 195 (KMJ battle) preloads it'),
    66: ('Mileena', 'mk', 'maps 132 (her secret arena) and 195 (KMJ battle) preload it'),
    67: ('Jade', 'mk', 'map 195 (KMJ battle) preloads it'),
    68: ('Ermac', 'mk', 'map 108 (Ermac battle) preloads it'),
    69: ('Sub-Zero', 'mk', 'NPC model'),
    70: ('Smoke', 'mk', 'no sound bank of its own'),
    71: ('Johnny Cage (story)', 'mk', 'sound bank "cage"'),
    72: ('Raiden', 'mk', 'model "xbox_raiden"'),
    74: ('Jax', 'mk', 'sound bank "jax"; model has grenades and a revolver'),
    76: ('monk?', 'enemy', 'generic humanoid, instances 8; Shuffle/LDK QA: fought and died in Goro\'s Lair (then called Johnny Cage; the screenshot showed a monk)'),
    77: ('monk?', 'enemy', 'generic humanoid, instances 8; Wu Shi maps 103/104/107 preload it'),
    78: ('Johnny Cage', 'mk', 'model "johnny cage"; never spawned as an enemy yet'),
    79: ('Kung Lao look-alike', 'unknown', 'same materials as type 1'),
    80: ('pterodactyl', 'enemy', ''),
    81: ('Kintaro (morning star)', 'unknown', 'instances 1 like the player rows'),
    82: ('Scorpion', 'playable', 'move menu root 0x52; full player animation set'),
    83: ('Baraka', 'versus', ''),
    84: ('Reptile', 'versus', ''),
    85: ('Ermac', 'versus', ''),
    86: ('Johnny Cage (stone)', 'mk', ''),
    87: ('creature (front/back limbs)', 'enemy', ''),
    88: ('Sub-Zero', 'playable', 'move menu root 0x58; full player animation set'),
    89: ('Kitana', 'versus', ''),
    90: ('Johnny Cage', 'versus', ''),
}

UMKSM_TIER = {   # readme - UMKSM V.2.txt: 0 base, 1 the versus characters, 2 extra NPCs
    'Liu Kang': 0, 'Kung Lao': 0, 'Scorpion': 0, 'Sub-Zero': 0,
    'Baraka': 1, 'Kitana': 1, 'Johnny Cage': 1, 'Reptile': 1, 'Ermac': 1,
    'Raiden': 2, 'Mileena': 2, 'Jade': 2, 'Smoke': 2, 'Kano': 2, 'Shao Kahn': 2,
    'Noob Saibot': 2, 'Kintaro': 2, 'Shang Tsung': 2,
}


def u32(va):
    return struct.unpack('<I', x.read(va, 4))[0]


def rid(engine_id):
    """pwf.py record index of an engine file id, or None."""
    return None if engine_id in (0, NONE) else engine_id - WAD_SHIFT


def model_tag(record):
    if record is None:
        return ''
    body = pwf.decoded(record)
    if not body:
        return ''
    skip = re.compile(r'^(Material|dummy|Box\d|default|efault|Default|Cylinder|lids|flap|Sphere|pelvis|abdomen|chest|neck|head|[lr]_)')
    words = [s for s in pwf.strings(body, 4)
             if re.match(r'^[A-Za-z][A-Za-z0-9 _\-]{3,}$', s) and not skip.match(s)]
    return ' '.join(words[:4])


def group(t, fx):
    """The type's run of WAD records: from its fx record to the next type's."""
    nxt = u32(CHAR_TABLE + (t + 1) * CHAR_ROW + 0x1C) if t + 1 < TYPES else fx + 10
    out = {}
    for r in range(fx - WAD_SHIFT, nxt - WAD_SHIFT):
        name, _, length = pwf.name(r)
        for suffix, kind in (('_sf.dat', 'sound'), ('nim.rtt', 'anim')):
            if name.endswith(suffix):
                out.setdefault(kind, (name, length or 0))
    return out


def maps():
    """map id -> (cap, preload list); descriptors live in .data."""
    out = {}
    for m in range(256):
        desc = u32(MAP_TABLE + m * 4)
        if not 0x4F0000 <= desc < 0x520000 or u32(desc + 0x44) != m:
            continue
        cap, ids = u32(desc + 0x20), []
        for k in range(8):
            v = u32(desc + 0x24 + k * 4)
            if v == NONE:
                break
            ids.append(v)
        out[m] = (cap, ids)
    return out


def debug_battles():
    out = {}
    va = DEBUG_MENU
    while u32(va) != 0:
        out[u32(va + 4)] = x.cstr(u32(va), 40)
        va += 8
    return out


def mod_sets():
    """type -> mod roles, read from the mod sources."""
    roles = {}
    core = open(os.path.join(ROOT, 'mods', '_build', 'src', 'core.lua'), encoding='utf-8').read()
    for table, label in (('SUPER_BOSSES', 'LDK/Shuffle boss'), ('MK_BOSSES', 'LDK/Shuffle boss')):
        body = re.search(r'local %s = \{(.*?)\n\}' % table, core, re.S).group(1)
        for t in re.findall(r'\[(\d+)\] = true', body):
            roles.setdefault(int(t), set()).add(label)
    outsiders = re.search(r'local OUTSIDERS = \{([^}]*)\}', core).group(1)
    for t in re.findall(r'\d+', outsiders):
        roles.setdefault(int(t), set()).add('Shuffle outsider')
    rifts = open(os.path.join(ROOT, 'mods', '_build', 'src', 'time_rifts_body.lua'), encoding='utf-8').read()
    consts = {k: int(v) for k, v in re.findall(r'local (\w+)\s*=\s*(\d+)\b', rifts)}
    for names in re.findall(r'bosses = \{([^}]*)\}', rifts):
        for name in re.findall(r'\w+', names):
            if name in consts:
                roles.setdefault(consts[name], set()).add('Time Rifts boss')
    return {t: sorted(v) for t, v in roles.items()}


def unkillable_types():
    """Types whose AI setup case clears the actor's can-kill byte (+0xD4)."""
    assert x.read(AI_SETUP_JUMP, 7) == b'\xff\x24\x85' + struct.pack('<I', AI_SETUP_TABLE), 'AI setup switch moved'
    cases = {}
    for i in range(AI_SETUP_CASES):
        cases.setdefault(u32(AI_SETUP_TABLE + i * 4), []).append(i + 2)
    starts = sorted(cases) + [AI_SETUP_TABLE]
    out = set()
    for k, start in enumerate(starts[:-1]):
        for ins in x.dis(start, 5000):
            if ins.address >= starts[k + 1]:
                break
            if ins.mnemonic == 'mov' and ins.op_str.startswith('byte ptr [') and ins.op_str.endswith('+ 0xd4], 0'):
                out.update(cases[start])
    return out


def build():
    all_maps = maps()
    battles = debug_battles()
    roles = mod_sets()
    unkillable = unkillable_types()
    rows = []
    for t in range(TYPES):
        row = CHAR_TABLE + t * CHAR_ROW
        assert u32(row) == 0x20004 + t, 'character table moved'
        f = [u32(row + o) for o in range(0, CHAR_ROW, 4)]
        snd = [u32(SOUND_TABLE + t * SOUND_ROW + o) for o in range(0, 16, 4)]
        grp = group(t, f[7])
        sound = pwf.name(rid(snd[1]))[0] if rid(snd[1]) is not None else ''
        if not sound.endswith('_sf.dat'):
            sound = grp.get('sound', ('', 0))[0]
        name, role, evidence = CURATED.get(t, ('', 'enemy' if 2 <= t <= 49 else 'unknown', ''))
        preloaded = [m for m, (_, ids) in sorted(all_maps.items()) if t in ids]
        base = name.split(' (')[0]
        rows.append({
            'type': t,
            'name': name,
            'role': role,
            'slots': f[1],
            'instances': f[2],
            'killable': 'no' if t in unkillable else 'yes',
            'sound_bank': sound.replace('_sf.dat', ''),
            'model_tag': model_tag(rid(f[3])),
            'anim_kb': grp.get('anim', ('', 0))[1] // 1024,
            'model_id': '%#x' % f[3], 'tex_id': '%#x' % f[4],
            'alt_model_id': '' if f[5] in (0, NONE) else '%#x' % f[5],
            'alt_tex_id': '' if f[6] in (0, NONE) else '%#x' % f[6],
            'fx_id': '' if f[7] in (0, NONE) else '%#x' % f[7],
            'preloaded_in': ' '.join(map(str, preloaded)),
            'boss_battle': '; '.join('%s (map %d)' % (battles[m], m) for m in preloaded if m in battles),
            'mods': '; '.join(roles.get(t, [])),
            'umksm_tier': '' if role not in ('player', 'playable', 'versus', 'mk', 'boss') else UMKSM_TIER.get(base, ''),
            'evidence': evidence,
        })
    return rows, all_maps, battles


def write(rows, all_maps, battles):
    with open(os.path.join(HERE, 'roster.csv'), 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(HERE, 'roster.json'), 'w', encoding='utf-8') as fh:
        json.dump({'types': rows,
                   'maps': {m: {'cap': cap, 'preload': ids} for m, (cap, ids) in sorted(all_maps.items())},
                   'debug_menu_battles': {m: label for m, label in sorted(battles.items())}},
                  fh, indent=1)
        fh.write('\n')
    lines = ['-- Generated by analysis/mk_roster/build_roster.py; do not edit.',
             '-- Shaolin Monks character types: type = character table row (spawn entry',
             '-- +0x00, preload lists, LOADED_TYPES, modelstream, entity +0x1DFE).',
             '-- slots = memory slots it needs; instances = character table +0x08;',
             '-- killable = false: its AI setup clears actor +0xD4, so its health stops at 1.',
             'return {']
    for r in rows:
        if not r['name']:
            continue
        lines.append('    [%d] = { name = %s, role = "%s", slots = %d, instances = %d, killable = %s },'
                     % (r['type'], json.dumps(r['name']), r['role'], r['slots'], r['instances'],
                        'true' if r['killable'] == 'yes' else 'false'))
    lines.append('}')
    with open(os.path.join(HERE, 'roster.lua'), 'w', newline='\n', encoding='utf-8') as fh:
        fh.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    rows, all_maps, battles = build()
    write(rows, all_maps, battles)
    named = sum(1 for r in rows if r['name'])
    print('roster: %d types (%d named), %d maps, %d debug-menu battles' % (len(rows), named, len(all_maps), len(battles)))
