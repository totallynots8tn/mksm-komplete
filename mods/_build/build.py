"""Rebuild the routine mods from mods/_build.

  python build.py          assemble scripts, refresh pack/ folders, write dist/*.tar.xz
  python build.py mksmk_probe   rebuild only the named mod folders

ldk and randomizer share src/core.lua; edit it once and rebuild.
Tests (any Lua 5.3+/5.4 interpreter, e.g. lua54 or texlua), run from this folder:
  lua tests/sim.lua ../ldk/pack/scripts/ldk.lua            (env: FREE=1 memory freed on death, NOLOADHOOK=1, BIG=1 full 50x22 level, WUSHI=1 one type fully booked)
  lua tests/env.lua
  lua tests/coop.lua ../coop_solo/pack/scripts/coop_solo.lua
"""
import hashlib, io, json, lzma, pathlib, sys, tarfile

HERE = pathlib.Path(__file__).resolve().parent
MODS = HERE.parent
SRC = HERE / 'src'
GAME = {"title": "Mortal Kombat: Shaolin Monks (USA, Europe)",
        "xbe_sha256": "48240902bf4a04eb89376217c529531032d3370749bcce91a194878cc49db74a"}

def text(name):
    return (SRC / name).read_text(encoding='utf-8')

def assemble(*parts):
    return ''.join(text(p) for p in parts) + '\nreturn hooks\n'

def ldk_variant(multiplier):
    source = assemble('core.lua', 'ldk_body.lua')
    for old, new in (('local MULTIPLIER       = 2', f'local MULTIPLIER       = {multiplier}'),
                     ('local BOSS_MULTIPLIER = 2', f'local BOSS_MULTIPLIER = {multiplier}')):
        assert source.count(old) == 1, old
        source = source.replace(old, new)
    return source

LDK_SUMMARY = ("{x}: enemy groups get {x} as many enemies as reinforcements, with Boss Invasion "
    "built in. Boss fights stay vanilla. Super bosses only appear in their own arena. "
    "Every extra enemy must fit in memory left over after the area's own spawns, so authored "
    "enemies are never starved and the game doesn't crash. Install all three variants; enable one.")

# Shaolin Shuffle ships as three conflicting variants (outsiders per room); one is enabled.
# Outsider pools (0.9): Normal keeps the v1 pool; Wild adds the regular types
# the QA logs saw as commons in 7+ areas; Chaos adds every type seen as a common.
OUTSIDERS_V1 = [10, 11, 12, 13, 14, 15, 26, 27]
OUTSIDERS_WILD = OUTSIDERS_V1 + [18, 42, 43]
OUTSIDERS_CHAOS = OUTSIDERS_WILD + [4, 8, 9, 17, 22, 30]
SHUFFLE_LEVELS = {
    'randomizer':       dict(minimum=1, chance=25, per_group=3, total=30, pool=OUTSIDERS_V1,
                             mix_room=0, mix_total=0),
    'randomizer_wild':  dict(minimum=1, chance=50, per_group=5, total=45, pool=OUTSIDERS_WILD,
                             mix_room=1, mix_total=24),
    'randomizer_chaos': dict(minimum=2, chance=80, per_group=8, total=60, pool=OUTSIDERS_CHAOS,
                             mix_room=2, mix_total=40),
}

def shuffle_variant(minimum, chance, per_group, total, pool, mix_room, mix_total):
    source = assemble('core.lua', 'randomizer_body.lua')
    for old, new in (('local OUTSIDER_MIN       = 1 ', f'local OUTSIDER_MIN       = {minimum} '),
                     ('local OUTSIDER_CHANCE    = 25 ', f'local OUTSIDER_CHANCE    = {chance} '),
                     ('local OUTSIDER_PER_GROUP = 3\n', f'local OUTSIDER_PER_GROUP = {per_group}\n'),
                     ('local OUTSIDER_TOTAL     = 30\n', f'local OUTSIDER_TOTAL     = {total}\n'),
                     ('local MIX_PER_ROOM       = 0 ', f'local MIX_PER_ROOM       = {mix_room} '),
                     ('local MIX_TOTAL          = 0 ', f'local MIX_TOTAL          = {mix_total} '),
                     ('local OUTSIDERS          = { 10, 11, 12, 13, 14, 15, 26, 27 }\n',
                      'local OUTSIDERS          = { ' + ', '.join(map(str, pool)) + ' }\n')):
        assert source.count(old) == 1, old
        source = source.replace(old, new)
    return source

SHUFFLE_SUMMARY = ("{level}: swaps enemy types between spawn slots that behave the same, and trades plain "
    "spawn slots between rooms so a room that authors one enemy type spawns several ({detail}). "
    "Areas with a single regular type (like Goro's Lair) get an outsider enemy type from another level "
    "instead. Per-type totals never change, so memory use stays vanilla; bosses keep their places. "
    "Install all three variants; enable one.")

def with_save(name, index=1):
    helper = text('probe_save.lua')
    assert helper.count('local SAVE_INDEX = 1 ') == 1
    return helper.replace('local SAVE_INDEX = 1 ', f'local SAVE_INDEX = {index} ') + text(name)

# Recomp runs at most 64 routine scripts across all enabled mods; the v1 set
# uses 5 besides the probe, so the probe must stay well under 59.
ROUTINE_LIMIT = 64
HEARTBEATS = 12     # one every ~15 minutes of gameplay: about 3 hours (0.11.2; was 24 x 7.5 min)
SAVESTATS = 20      # one per statue save

def heartbeat(index):
    source = text('probe_heartbeat.lua')
    assert source.count('local HB_INDEX      = 1 ') == 1
    return source.replace('local HB_INDEX      = 1 ', f'local HB_INDEX      = {index} ')

def numbered(name, index):
    return f'{name}.lua' if index == 1 else f'{name}_{index}.lua'

# folder, id, name, readme, version, summary, {script: source}, extra manifest fields
MODLIST = [
    ('ldk', 'ldk', 'Legendary Dark Knight Mode', 'ldk.md', '3.11.0', LDK_SUMMARY.format(x='x2'),
     {'ldk.lua': lambda: ldk_variant(2)}, {'conflicts': ['ldk_x3', 'ldk_x4']}),
    ('ldk_x3', 'ldk_x3', 'Legendary Dark Knight Mode (x3 Hard)', 'ldk.md', '3.11.0', LDK_SUMMARY.format(x='x3'),
     {'ldk.lua': lambda: ldk_variant(3)}, {'conflicts': ['ldk', 'ldk_x4']}),
    ('ldk_x4', 'ldk_x4', 'Legendary Dark Knight Mode (x4 Legendary)', 'ldk.md', '3.11.0', LDK_SUMMARY.format(x='x4'),
     {'ldk.lua': lambda: ldk_variant(4)}, {'conflicts': ['ldk', 'ldk_x3']}),
    ('randomizer', 'randomizer', 'Shaolin Shuffle (Enemy Randomizer)', 'randomizer.md', '0.10.0',
     SHUFFLE_SUMMARY.format(level='Normal', detail='a modest swap: slots keep their room, single-type areas get an outsider'),
     {'randomizer.lua': lambda: shuffle_variant(**SHUFFLE_LEVELS['randomizer'])},
     {'conflicts': ['randomizer_wild', 'randomizer_chaos']}),
    ('randomizer_wild', 'randomizer_wild', 'Shaolin Shuffle (Wild)', 'randomizer.md', '0.10.0',
     SHUFFLE_SUMMARY.format(level='Wild', detail='every one-type room trades a slot with another room, so rooms spawn several types; single-type areas get outsiders from 11 enemy types'),
     {'randomizer.lua': lambda: shuffle_variant(**SHUFFLE_LEVELS['randomizer_wild'])},
     {'conflicts': ['randomizer', 'randomizer_chaos']}),
    ('randomizer_chaos', 'randomizer_chaos', 'Shaolin Shuffle (Chaos)', 'randomizer.md', '0.10.0',
     SHUFFLE_SUMMARY.format(level='Chaos', detail='every one-type room trades up to two slots and most plain spawns move, from every one of the 17 regular enemy types seen as common enemies'),
     {'randomizer.lua': lambda: shuffle_variant(**SHUFFLE_LEVELS['randomizer_chaos'])},
     {'conflicts': ['randomizer', 'randomizer_wild']}),
    ('env_kill_xp', 'env_kill_xp', 'Environmental Kill XP', 'env_kill_xp.md', '2.0.0',
     "Hazard kills (pits, spikes, saws, fire, dismemberment, enemies thrown off the map) count exactly like normal kills: each adds its XP (50 for most enemies) to your combo, gets the combo multiplier and shows the normal XP popup.",
     {'env_kill_xp.lua': lambda: text('env_kill_xp.lua')}, {}),
    ('coop_solo', 'coop_solo', 'Solo Co-op Paths', 'coop_solo.md', '0.6.2',
     "Experimental: in single player, level layout scripts are told it's co-op (istwoplayer yes, isoneplayer no) so they choose co-op layouts and secret routes, but map-trigger conditions still see the real player count so solo-progression plates can fire. 0.5 also rewrites a co-op plate's player-2 trigger conditions into copies of the player-1 condition. Co-op plates work in single player: colored plates of either player's color activate, and a plate stays pressed for about 15 seconds after you step off, so one player can stand on each plate in turn. Engine-side co-op logic stays single player.",
     {'coop_solo.lua': lambda: text('coop_solo.lua')}, {}),
    ('time_rifts', 'time_rifts', 'Time Rifts (preview)', 'time_rifts.md', '0.2.0',
     "Experimental: the co-op rift portals in Wu Shi (map 1) and Goro's Lair (map 100) reload their current area through the game's own loader instead of leading to their destination, so the area's authored enemies and Goro's encounter can be fought again; with Legendary Dark Knight enabled those groups are filled as reinforcements. No boss AI is moved between arenas and no progression is changed. Needs Solo Co-op Paths to reach the portals in single player.",
     {'time_rifts.lua': lambda: text('time_rifts.lua')}, {}),
    ('mk_upgrade', 'mk_upgrade', 'Extended Upgrades: XP Shop (preview)', 'upgrade.md', '0.11.0',
     "Experimental XP shop; everything it sells comes on top of what the game gives. Pause > Moves > Basic Moves becomes Upgrades: Health +1 to +4 (5,000 / 10,000 / 15,000 / 20,000 XP; +100 / +200 / +400 / +800 max health in solo, above the game's own four, applied at once) and Stamina +1 to +4 (same costs; blocks, specials and the long jump cost less, as if the blue bar held 125 / 150 / 200 / 300%; each co-op player buys their own). Running Attacks becomes Weapons: summon a weapon lying in the current area to where you stand (2,000 XP, again and again). Fatalities you haven't discovered can be bought (5,000 XP each), which reveals their input. Every Specials row (X, Y, B) can be bought a second time as its EX move, in any order, once you own the move (5,000 XP and up); L2 + that move's input (no R2) does it as an EX, for extra stamina once per move: 10x damage, a short impact pause and three times as fast a recovery (experimental). Skill and Team stay vanilla. Bought through the game's own Upgrade dialog. Labels in the game's language (EN/ES/DE/IT/FR). Uses no content files, so it works alongside language packs (if a pack has no room for the labels, the menu stays vanilla).",
     {'upgrade.lua': lambda: text('upgrade.lua')}, {}),
    ('mksmk_probe', 'mksmk_probe', 'MKSMK Probe (diagnostics)', 'probe.md', '0.12.0',
     "Diagnostics only, changes nothing: records kills, XP awards and enemy spawns, traces the map triggers behind co-op plates, snapshots the shuffle eligibility of every area you visit, and samples the dismember/brutality/upgrade command signatures, and watches the save data for every value that changes (XP, upgrades, abilities). Reports are written to the session log at your first, second and third save; 0.11 adds a heartbeat (every 15 minutes of play since 0.11.2, which frees 12 of the 64 script slots) (so a soft-lock or crash between saves still leaves data) and the XP balance and playtime of every save.",
     {'probe_events.lua': lambda: with_save('probe_body.lua', 1),
      'probe_events_2.lua': lambda: with_save('probe_body.lua', 2),
      'probe_events_3.lua': lambda: with_save('probe_body.lua', 3),
      'probe_savediff.lua': lambda: with_save('probe_savediff.lua', 1),
      'probe_savediff_2.lua': lambda: with_save('probe_savediff.lua', 2),
      'probe_savediff_3.lua': lambda: with_save('probe_savediff.lua', 3),
      'probe_upgrade_2.lua': lambda: with_save('probe_upgrade.lua', 2),
      'probe_plate.lua': lambda: with_save('probe_plate.lua'),
      'probe_shuffle.lua': lambda: with_save('probe_shuffle.lua'),
      'probe_upgrade.lua': lambda: with_save('probe_upgrade.lua')}
     | {numbered('probe_heartbeat', i): (lambda i=i: heartbeat(i)) for i in range(1, HEARTBEATS + 1)}
     | {numbered('probe_savestat', i): (lambda i=i: with_save('probe_savestat.lua', i)) for i in range(1, SAVESTATS + 1)},
     {}),
]
ORDER = ['id', 'name', 'summary', 'authors', 'type', 'install_dir', 'features', 'routines', 'conflicts',
         'schema', 'version', 'recomp', 'game', 'patches', 'files']

ONLY = set(sys.argv[1:])    # python build.py mksmk_probe: rebuild only those folders

for folder, mid, name, readme, version, summary, scripts, extra in MODLIST:
    if ONLY and folder not in ONLY:
        continue
    pack = MODS / folder / 'pack'
    manifest_path = pack / 'mod.json'
    if manifest_path.exists():
        m = json.loads(manifest_path.read_text(encoding='utf-8'))
    else:
        m = {'id': mid, 'name': name, 'authors': ['MKSMK'], 'type': 'gameplay', 'install_dir': f'packages/{mid}',
             'features': ['lua'], 'schema': 2, 'recomp': '0.2.0', 'game': GAME, 'patches': []}
    payload = {f'scripts/{s}': build().encode('utf-8') for s, build in scripts.items()}
    payload['README.md'] = (HERE / 'readme' / readme).read_bytes()
    m.pop('conflicts', None)
    m.update(extra, version=version, summary=summary, routines=[f'scripts/{s}' for s in scripts])
    assert len(scripts) <= ROUTINE_LIMIT - 8, f'{mid}: {len(scripts)} routines leave too little of the {ROUTINE_LIMIT}-script limit'
    m['files'] = [{'path': p, 'size': len(d), 'sha256': hashlib.sha256(d).hexdigest()} for p, d in payload.items()]
    m = {k: m[k] for k in ORDER if k in m} | {k: v for k, v in m.items() if k not in ORDER}
    manifest = json.dumps(m, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    (pack / 'scripts').mkdir(parents=True, exist_ok=True)
    manifest_path.write_bytes(manifest)
    for path, data in payload.items():
        (pack / path).write_bytes(data)
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w', format=tarfile.PAX_FORMAT) as tar:
        entries = [('mod.json', manifest), ('README.md', payload['README.md'])]
        entries += [(p, d) for p, d in payload.items() if p != 'README.md']
        for entry, data in entries:
            info = tarfile.TarInfo(entry); info.size = len(data); info.mode = 0o644; info.mtime = 0
            tar.addfile(info, io.BytesIO(data))
    packed = lzma.compress(buffer.getvalue(), format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC64,
                           preset=9 | lzma.PRESET_EXTREME)
    dist = MODS / folder / 'dist'
    dist.mkdir(exist_ok=True)
    (dist / f"{m['id']}-{version}.tar.xz").write_bytes(packed)
    print(f"{m['id']} {version}: {len(packed)} bytes")
