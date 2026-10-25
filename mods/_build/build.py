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
SHUFFLE_LEVELS = {
    'randomizer':       dict(minimum=1, chance=25, per_group=3, total=30),
    'randomizer_wild':  dict(minimum=1, chance=50, per_group=5, total=45),
    'randomizer_chaos': dict(minimum=2, chance=80, per_group=8, total=60),
}

def shuffle_variant(minimum, chance, per_group, total):
    source = assemble('core.lua', 'randomizer_body.lua')
    for old, new in (('local OUTSIDER_MIN       = 1 ', f'local OUTSIDER_MIN       = {minimum} '),
                     ('local OUTSIDER_CHANCE    = 25 ', f'local OUTSIDER_CHANCE    = {chance} '),
                     ('local OUTSIDER_PER_GROUP = 3\n', f'local OUTSIDER_PER_GROUP = {per_group}\n'),
                     ('local OUTSIDER_TOTAL     = 30\n', f'local OUTSIDER_TOTAL     = {total}\n')):
        assert source.count(old) == 1, old
        source = source.replace(old, new)
    return source

SHUFFLE_SUMMARY = ("{level}: shuffles enemy types across every spawn slot of the area, and brings in an "
    "outsider enemy type from another level where an area has only one regular type (like Goro's Lair): "
    "{detail}. Memory is checked for every spawn; bosses keep their places. "
    "Install all three variants; enable one.")

def with_save(name, index=1):
    helper = text('probe_save.lua')
    assert helper.count('local SAVE_INDEX = 1 ') == 1
    return helper.replace('local SAVE_INDEX = 1 ', f'local SAVE_INDEX = {index} ') + text(name)

# Recomp runs at most 64 routine scripts across all enabled mods; the v1 set
# uses 5 besides the probe, so the probe must stay well under 59.
ROUTINE_LIMIT = 64
HEARTBEATS = 24     # one every ~7.5 minutes of gameplay: about 3 hours
SAVESTATS = 20      # one per statue save

def heartbeat(index):
    source = text('probe_heartbeat.lua')
    assert source.count('local HB_INDEX      = 1 ') == 1
    return source.replace('local HB_INDEX      = 1 ', f'local HB_INDEX      = {index} ')

def numbered(name, index):
    return f'{name}.lua' if index == 1 else f'{name}_{index}.lua'

# folder, id, name, readme, version, summary, {script: source}, extra manifest fields
MODLIST = [
    ('ldk', 'ldk', 'Legendary Dark Knight Mode', 'ldk.md', '3.9.2', LDK_SUMMARY.format(x='x2'),
     {'ldk.lua': lambda: ldk_variant(2)}, {'conflicts': ['ldk_x3', 'ldk_x4']}),
    ('ldk_x3', 'ldk_x3', 'Legendary Dark Knight Mode (x3 Hard)', 'ldk.md', '3.9.2', LDK_SUMMARY.format(x='x3'),
     {'ldk.lua': lambda: ldk_variant(3)}, {'conflicts': ['ldk', 'ldk_x4']}),
    ('ldk_x4', 'ldk_x4', 'Legendary Dark Knight Mode (x4 Legendary)', 'ldk.md', '3.9.2', LDK_SUMMARY.format(x='x4'),
     {'ldk.lua': lambda: ldk_variant(4)}, {'conflicts': ['ldk', 'ldk_x3']}),
    ('randomizer', 'randomizer', 'Shaolin Shuffle (Enemy Randomizer)', 'randomizer.md', '0.8.2',
     SHUFFLE_SUMMARY.format(level='Normal', detail='one or more outsiders in every room, about a quarter of the spawns'),
     {'randomizer.lua': lambda: shuffle_variant(**SHUFFLE_LEVELS['randomizer'])},
     {'conflicts': ['randomizer_wild', 'randomizer_chaos']}),
    ('randomizer_wild', 'randomizer_wild', 'Shaolin Shuffle (Wild)', 'randomizer.md', '0.8.2',
     SHUFFLE_SUMMARY.format(level='Wild', detail='one or more outsiders in every room, about half the spawns'),
     {'randomizer.lua': lambda: shuffle_variant(**SHUFFLE_LEVELS['randomizer_wild'])},
     {'conflicts': ['randomizer', 'randomizer_chaos']}),
    ('randomizer_chaos', 'randomizer_chaos', 'Shaolin Shuffle (Chaos)', 'randomizer.md', '0.8.2',
     SHUFFLE_SUMMARY.format(level='Chaos', detail='two or more outsiders in every room, most of the spawns'),
     {'randomizer.lua': lambda: shuffle_variant(**SHUFFLE_LEVELS['randomizer_chaos'])},
     {'conflicts': ['randomizer', 'randomizer_wild']}),
    ('env_kill_xp', 'env_kill_xp', 'Environmental Kill XP', 'env_kill_xp.md', '2.0.0',
     "Hazard kills (pits, spikes, saws, fire, dismemberment, enemies thrown off the map) count exactly like normal kills: each adds its XP (50 for most enemies) to your combo, gets the combo multiplier and shows the normal XP popup.",
     {'env_kill_xp.lua': lambda: text('env_kill_xp.lua')}, {}),
    ('coop_solo', 'coop_solo', 'Solo Co-op Paths', 'coop_solo.md', '0.6.2',
     "Experimental: in single player, level layout scripts are told it's co-op (istwoplayer yes, isoneplayer no) so they choose co-op layouts and secret routes, but map-trigger conditions still see the real player count so solo-progression plates can fire. 0.5 also rewrites a co-op plate's player-2 trigger conditions into copies of the player-1 condition. Co-op plates work in single player: colored plates of either player's color activate, and a plate stays pressed for about 15 seconds after you step off, so one player can stand on each plate in turn. Engine-side co-op logic stays single player.",
     {'coop_solo.lua': lambda: text('coop_solo.lua')}, {}),
    ('mk_upgrade', 'mk_upgrade', 'Extended Upgrades (prototype)', 'upgrade.md', '0.1.0',
     "PROTOTYPE, experimental: the spine of a larger upgrade system. Extra XP from Legendary Dark Knight unlocks passive perks (blade dismemberment, brutality-anim EX moves, stamina) at XP thresholds. Effects are inert pending reverse-engineering; the mod writes nothing to game memory and is safe to install.",
     {'upgrade.lua': lambda: text('upgrade.lua')}, {}),
    ('mksmk_probe', 'mksmk_probe', 'MKSMK Probe (diagnostics)', 'probe.md', '0.11.0',
     "Diagnostics only, changes nothing: records kills, XP awards and enemy spawns, traces the map triggers behind co-op plates, snapshots the shuffle eligibility of every area you visit, and samples the dismember/brutality/upgrade command signatures, and watches the save data for every value that changes (XP, upgrades, abilities). Reports are written to the session log at your first, second and third save; 0.11 adds a heartbeat about every 7 minutes of play (so a soft-lock or crash between saves still leaves data) and the XP balance and playtime of every save.",
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
