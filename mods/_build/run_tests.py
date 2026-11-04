"""Build every mod and run every offline test; exit 1 if any fails.

  python run_tests.py            build, then run all tests
  python run_tests.py --no-build run the tests on the packs already built
  python run_tests.py sim upgrade   only the cases whose name starts with one of these

Uses the Lua 5.4 interpreter (lua, lua54, or the one under %LOCALAPPDATA%),
else lupa through run_lua.py. Sim cases pass when the sim reports no script
errors, crashes or stuck groups.
"""
import os, shutil, subprocess, sys, pathlib

HERE = pathlib.Path(__file__).resolve().parent
PACK = '../{}/pack/scripts/{}'


def lua_command():
    for name in ('lua54', 'lua'):
        found = shutil.which(name)
        if found:
            return [found]
    local = pathlib.Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs' / 'Lua' / 'bin' / 'lua.exe'
    if local.is_file():
        return [str(local)]
    return [sys.executable, 'run_lua.py']


def probe(name):
    return PACK.format('mksmk_probe', name)


SIM_CLEAN = ('script errors:\t0', 'CRASHES (heap exhausted):\t0', 'stuck groups:\t0')
LDK2, LDK3, LDK4 = PACK.format('ldk', 'ldk.lua'), PACK.format('ldk_x3', 'ldk.lua'), PACK.format('ldk_x4', 'ldk.lua')
SHUFFLE = PACK.format('randomizer', 'randomizer.lua')
RIFTS = PACK.format('time_rifts', 'time_rifts.lua')
GAUNTLET = PACK.format('time_rifts', 'gauntlet.lua')

# name, test, args, environment, text the output must contain
CASES = [
    ('callgate', 'callgate.lua', [PACK.format('callgate_test', 'callgate.lua')], {}, ()),
    ('coop', 'coop.lua', [PACK.format('coop_solo', 'coop_solo.lua')], {}, ()),
    ('coop_latch', 'coop_latch.lua', [PACK.format('coop_solo', 'coop_solo.lua')], {}, ()),
    ('coop_plate', 'coop_plate.lua', [PACK.format('coop_solo', 'coop_solo.lua')], {}, ()),
    ('coop_stone', 'coop_stone.lua', [PACK.format('coop_solo', 'coop_solo.lua')], {}, ()),
    ('coop_debug', 'coop_debug.lua', ['src/coop_solo_debug.lua'], {}, ()),
    ('env', 'env.lua', [PACK.format('env_kill_xp', 'env_kill_xp.lua')], {}, ()),
    ('ldk_boss', 'ldk_boss.lua', [LDK3], {}, ()),
    ('pause_save', 'pause_save.lua', ['src/pause_save.lua'], {}, ()),
    ('portal_trace', 'portal_trace.lua', [PACK.format('portal_trace', 'portal_trace.lua')], {}, ()),
    ('probe_heartbeat', 'probe_heartbeat.lua', [probe('probe_heartbeat.lua'), probe('probe_heartbeat_2.lua')], {}, ()),
    ('probe_save', 'probe_save.lua', [probe('probe_events.lua'), 'EVENTS'], {}, ()),
    ('probe_savediff', 'probe_savediff.lua', [probe('probe_savediff.lua'), probe('probe_savediff_2.lua')], {}, ()),
    ('probe_savestat', 'probe_savestat.lua', [probe('probe_savestat.lua'), probe('probe_savestat_2.lua')], {}, ()),
    ('probe_shuffle', 'probe_shuffle.lua', [probe('probe_shuffle.lua')], {}, ()),
    ('probe_upgrade', 'probe_upgrade.lua', [probe('probe_upgrade.lua')], {}, ()),
    ('shuffle_outsider', 'shuffle_outsider.lua', [SHUFFLE], {}, ()),
    ('time_rifts_110', 'time_rifts_rift.lua', [RIFTS, '110', 'beaten'], {}, ()),
    ('time_rifts_132', 'time_rifts_rift.lua', [RIFTS, '132', 'beaten'], {}, ()),
    ('time_rifts_vanish', 'time_rifts_rift.lua', [RIFTS, '110', 'vanish'], {}, ()),
    ('time_rifts_vanish_132', 'time_rifts_rift.lua', [RIFTS, '132', 'vanish'], {}, ()),
    ('time_rifts_failed', 'time_rifts_rift.lua', [RIFTS, '110', 'failed'], {}, ()),
    ('time_rifts_left', 'time_rifts_rift.lua', [RIFTS, '132', 'left'], {}, ()),
    ('time_rifts_stuck_132', 'time_rifts_rift.lua', [RIFTS, '132', 'stuck'], {}, ()),
    ('time_rifts_pack_199', 'time_rifts_pack.lua', [RIFTS], {}, ()),
    ('time_rifts_rush_beaten', 'time_rifts_rush.lua', [RIFTS, 'beaten'], {}, ()),
    ('time_rifts_rush_english', 'time_rifts_rush.lua', [RIFTS, 'english'], {}, ()),
    ('time_rifts_rush_noroom', 'time_rifts_rush.lua', [RIFTS, 'noroom'], {}, ()),
    ('time_rifts_rush_failed', 'time_rifts_rush.lua', [RIFTS, 'failed'], {}, ()),
    ('time_rifts_rush_nogoro', 'time_rifts_rush.lua', [RIFTS, 'nogoro'], {}, ()),
    ('time_rifts_once', 'time_rifts_rift.lua', [RIFTS, '110', 'once'], {}, ()),
    ('time_rifts_gauntlet_beaten', 'gauntlet.lua', [GAUNTLET, 'beaten'], {}, ()),
    ('time_rifts_gauntlet_portal', 'gauntlet.lua', [GAUNTLET, 'portal'], {}, ()),
    ('time_rifts_gauntlet_closed', 'gauntlet.lua', [GAUNTLET, 'closed'], {}, ()),
    ('upgrade', 'upgrade.lua', ['src/upgrade.lua'], {}, ()),
    ('upgrade_parts', 'upgrade_parts.lua', [PACK.format('mk_upgrade', 'upgrade.lua'),
                                            PACK.format('mk_upgrade', 'upgrade_ex.lua'), 'src/upgrade.lua'], {}, ()),
    # the spawn sim: LDK and Shuffle alone and together, in the level shapes it knows
    ('sim_ldk_x2', 'sim.lua', [LDK2], {}, SIM_CLEAN),
    ('sim_ldk_x3', 'sim.lua', [LDK3], {}, SIM_CLEAN),
    ('sim_ldk_x4', 'sim.lua', [LDK4], {}, SIM_CLEAN),
    ('sim_shuffle', 'sim.lua', [SHUFFLE], {}, SIM_CLEAN),
    ('sim_both', 'sim.lua', [LDK3, SHUFFLE], {}, SIM_CLEAN),
    ('sim_both_x4_big', 'sim.lua', [LDK4, SHUFFLE], {'BIG': '1'}, SIM_CLEAN),
    ('sim_both_wushi', 'sim.lua', [LDK3, SHUFFLE], {'WUSHI': '1'}, SIM_CLEAN),
    ('sim_both_bosses', 'sim.lua', [LDK3, SHUFFLE], {'BOSSES': '1'}, SIM_CLEAN),
    ('sim_both_fatality', 'sim.lua', [LDK3, SHUFFLE], {'FATALITY': '1'}, SIM_CLEAN),
    ('sim_both_carry', 'sim.lua', [LDK3, SHUFFLE], {'CARRY': '1'}, SIM_CLEAN),
    ('sim_ldk_lair', 'sim.lua', [LDK3], {'LAIR': '1', 'CARRY': '1'}, SIM_CLEAN),
    ('sim_shuffle_outsider', 'sim.lua', [SHUFFLE], {'OUTSIDER': '1'}, SIM_CLEAN),
    ('sim_both_outsider_evict', 'sim.lua', [LDK3, SHUFFLE], {'OUTSIDER': '1', 'OUTSIDER_EVICT': '1'}, SIM_CLEAN),
    ('sim_shuffle_mix', 'sim.lua', [SHUFFLE], {'MIX': '1'}, SIM_CLEAN),
    ('sim_both_mix', 'sim.lua', [LDK3, SHUFFLE], {'MIX': '1'}, SIM_CLEAN),
    ('sim_both_rift', 'sim.lua', [LDK3, SHUFFLE], {'RIFT': '1'}, SIM_CLEAN + ('rift group untouched',)),
    ('sim_both_rift_outsider', 'sim.lua', [LDK4, SHUFFLE], {'RIFT': '1', 'OUTSIDER': '1'}, SIM_CLEAN + ('rift group untouched',)),
    # Mortal Kombat warriors (Shuffle 0.12): killable, at most two entries, never more alive than the slot holds
    ('sim_shuffle_warrior', 'sim.lua', [SHUFFLE], {'OUTSIDER': '1', 'WARRIOR': '1'}, SIM_CLEAN + ('warriors ok',)),
    ('sim_shuffle_warrior_two', 'sim.lua', [SHUFFLE], {'OUTSIDER': '1', 'OUTSIDER_TWO': '1', 'WARRIOR': '1'}, SIM_CLEAN + ('warriors ok',)),
    ('sim_both_warrior_copies', 'sim.lua', [LDK3, SHUFFLE],
     {'OUTSIDER': '1', 'WARRIOR': '1', 'WARRIOR_COPIES': '1', 'WARRIOR_TOUGH': '1'}, SIM_CLEAN + ('warriors ok',)),
]


def main(argv):
    build = '--no-build' not in argv
    only = [a for a in argv if not a.startswith('--')]
    if build:
        done = subprocess.run([sys.executable, 'build.py'], cwd=HERE, capture_output=True, text=True)
        if done.returncode != 0:
            print(done.stdout + done.stderr)
            print('BUILD FAILED')
            return 1
    lua = lua_command()
    failed = []
    for name, test, args, env, needs in CASES:
        if only and not any(name.startswith(o) for o in only):
            continue
        run = subprocess.run(lua + ['tests/' + test] + args, cwd=HERE, capture_output=True, text=True,
                             env=dict(os.environ, **env))
        out = run.stdout + run.stderr
        missing = [n for n in needs if n not in out]
        ok = run.returncode == 0 and 'LUA ERROR' not in out and not missing
        print(('PASS ' if ok else 'FAIL ') + name)
        if not ok:
            failed.append(name)
            print('  ' + out.strip().replace('\n', '\n  ')[-3000:])
            for n in missing:
                print(f'  missing: {n!r}')
    print(f'{len(failed)} failed' if failed else 'all passed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
