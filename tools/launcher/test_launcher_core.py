"""Tests for launcher_core against throwaway Recomp data folders (never the real one).

  py -3 -m unittest discover -s tools/launcher -p "test_*.py"     (from the project folder)

They install the newest release/v1.x set, plus LDK x2/x4 built and verified
the way build_exe.py does it, into a temp folder and check installed.toml, the
package folders and `modtool.py list --data <temp>`.
"""
import json, shutil, subprocess, sys, tempfile, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_exe  # noqa: E402
import launcher_core as core  # noqa: E402
modtool = core.modtool

ROOT = HERE.parents[1]
RELEASE = core.newest_release(ROOT)


def rows_of(data):
    return {r["id"]: r for r in modtool.read_registry(data / "mods")}


def add_row(data, mid, version, routines=0, enabled=True, folder=True, extra=None):
    """Register a mod that isn't in the set (and make its folder), like a dev diagnostic."""
    manifest = {"id": mid, "name": mid.replace("_", " ").title(), "version": version, "type": "gameplay",
                "install_dir": f"packages/{mid}", "routines": [f"scripts/s{i}.lua" for i in range(routines)]}
    manifest.update(extra or {})
    rows = modtool.read_registry(data / "mods")
    rows.append({"id": mid, "version": version, "enabled": enabled, "raw": json.dumps(manifest), "manifest": manifest})
    modtool.write_registry(data / "mods", rows)
    if folder:
        target = data / "mods" / manifest["install_dir"]
        target.mkdir(parents=True, exist_ok=True)
        (target / "mod.json").write_text(json.dumps(manifest), encoding="utf-8")


def edit_row(data, mid, **changes):
    rows = modtool.read_registry(data / "mods")
    for r in rows:
        if r["id"] == mid:
            r["manifest"].update(changes)
            r["version"] = r["manifest"]["version"]
            r["raw"] = json.dumps(r["manifest"])
    modtool.write_registry(data / "mods", rows)


class LauncherCore(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assert RELEASE, "no release/v1.x folder with packages"
        cls.work = Path(tempfile.mkdtemp(prefix="mksmk-launcher-ldk-"))
        variants = cls.work / "variants"
        variants.mkdir()
        for archive in build_exe.ldk_variants(RELEASE, cls.work):
            shutil.copy2(archive, variants)
        cls.bundle, problems, _ = core.load_bundle([RELEASE, variants])
        assert not problems, problems

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work, ignore_errors=True)

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="mksmk-launcher-test-"))
        self.data = self.tmp / "data"
        (self.data / "mods").mkdir(parents=True)
        self._running = core.process_running
        core.process_running = lambda name=core.PROCESS: False

    def tearDown(self):
        core.process_running = self._running
        shutil.rmtree(self.tmp, ignore_errors=True)

    def fresh(self, prefs=None):
        return core.install_set(self.data, self.bundle, prefs or {})

    # ---------------------------------------------------------------- the set
    def test_bundle_has_the_set_and_three_ldk_levels(self):
        for mid in ("coop_solo", "env_kill_xp", "mk_upgrade", "mksmk_probe", "randomizer", "time_rifts",
                    "unlock_all", "ldk", "ldk_x3", "ldk_x4"):
            self.assertIn(mid, self.bundle)
        versions = {self.bundle[m]["manifest"]["version"] for m in core.LDK_IDS}
        self.assertEqual(len(versions), 1, "LDK variants must share one version")

    def test_old_packages_folder_cannot_downgrade(self):
        old = ROOT / "release" / "v1.2"
        if not any(old.glob("mk_upgrade-*.tar.xz")):
            self.skipTest("no release/v1.2 packages")
        bundle, _, _ = core.load_bundle([RELEASE, old])
        self.assertEqual(bundle["mk_upgrade"]["manifest"]["version"],
                         self.bundle["mk_upgrade"]["manifest"]["version"])
        names = [c.text() for c in core.plan(self.bundle, [])]
        self.assertIn("Install Legendary Dark Knight x2 " + self.bundle["ldk"]["manifest"]["version"], names)

    def test_readme(self):
        title, date, notes = core.set_info([RELEASE])
        self.assertTrue(title.startswith(RELEASE.name), title)
        self.assertRegex(date, r"^\d{4}-\d{2}-\d{2}$")
        self.assertIn("Time Rifts", notes)
        self.assertNotIn("Install from file", notes)

    # ---------------------------------------------------------------- Install
    def test_fresh_install_matches_modtool_list(self):
        result = self.fresh()
        self.assertEqual({c.kind for c in result.changes}, {"install"})
        self.assertEqual(len(result.changes), len(self.bundle))
        rows = rows_of(self.data)
        self.assertEqual(set(rows), set(self.bundle))
        off = {m for m, r in rows.items() if not r["enabled"]}
        self.assertEqual(off, {"ldk", "ldk_x4", "mksmk_probe"})
        for mid, package in self.bundle.items():
            folder = self.data / "mods" / package["manifest"]["install_dir"]
            self.assertTrue((folder / "mod.json").is_file(), mid)
            for f in package["manifest"]["files"]:
                self.assertTrue((folder / f["path"]).is_file(), f["path"])
        listed = subprocess.run([sys.executable, str(ROOT / "mods" / "_build" / "modtool.py"), "list",
                                 "--data", str(self.data)], capture_output=True, text=True, check=True).stdout
        lines = [ln.strip() for ln in listed.splitlines()[1:] if ln.strip()]
        self.assertEqual(len(lines), len(self.bundle))
        for mid, r in rows.items():
            line = f"[{'x' if r['enabled'] else ' '}] {r['manifest']['name']} {r['version']}"
            self.assertIn(line, lines)
        self.assertEqual(core.plan(self.bundle, modtool.read_registry(self.data / "mods")), [])

    def test_prefs_choose_level_and_switches(self):
        self.fresh({"on": {"time_rifts": False, "mksmk_probe": True}, "level": "x4"})
        rows = rows_of(self.data)
        self.assertFalse(rows["time_rifts"]["enabled"])
        self.assertTrue(rows["mksmk_probe"]["enabled"])
        self.assertEqual([m for m in core.LDK_IDS if rows[m]["enabled"]], ["ldk_x4"])

    def test_ldk_off_installs_all_levels_disabled(self):
        self.fresh({"on": {"ldk": False}})
        rows = rows_of(self.data)
        self.assertFalse(any(rows[m]["enabled"] for m in core.LDK_IDS))

    def test_update_keeps_newer_others_and_language_packs_removes_retired(self):
        self.fresh()
        edit_row(self.data, "randomizer", version="9.0.0")          # a newer dev build
        edit_row(self.data, "mk_upgrade", version="0.0.1")          # an old build
        add_row(self.data, "portal_trace", "0.4.0", routines=1)
        add_row(self.data, "es_pack", "1.0.0", extra={"type": "language", "install_dir": "languages/es_pack"})
        add_row(self.data, "randomizer_wild", "0.10.0", routines=1)
        plan = {c.id: c.kind for c in core.plan(self.bundle, modtool.read_registry(self.data / "mods"))}
        self.assertEqual(plan, {"mk_upgrade": "update", "randomizer_wild": "remove"})
        result = core.install_set(self.data, self.bundle, {})
        rows = rows_of(self.data)
        self.assertEqual(rows["randomizer"]["version"], "9.0.0")
        self.assertEqual(rows["mk_upgrade"]["version"], self.bundle["mk_upgrade"]["manifest"]["version"])
        self.assertIn("portal_trace", rows)
        self.assertIn("es_pack", rows)
        self.assertNotIn("randomizer_wild", rows)
        self.assertFalse((self.data / "mods" / "packages" / "randomizer_wild").exists())
        self.assertTrue((result.backup / "packages" / "randomizer_wild" / "mod.json").is_file())
        self.assertTrue((self.data / "mods" / "packages" / "portal_trace" / "mod.json").is_file())
        others = [r["id"] for r in core.others(self.bundle, modtool.read_registry(self.data / "mods"))]
        self.assertEqual(sorted(others), ["es_pack", "portal_trace"])

    def test_same_version_other_build_is_reinstalled(self):
        self.fresh()
        edit_row(self.data, "coop_solo", summary="a dev build")
        self.assertEqual([(c.id, c.kind) for c in core.plan(self.bundle, modtool.read_registry(self.data / "mods"))],
                         [("coop_solo", "reinstall")])

    def test_update_keeps_switch_states(self):
        self.fresh({"on": {"env_kill_xp": False}})
        edit_row(self.data, "env_kill_xp", version="0.0.1")
        core.install_set(self.data, self.bundle, {"on": {"env_kill_xp": True}})   # flags of installed mods win
        self.assertFalse(rows_of(self.data)["env_kill_xp"]["enabled"])

    def test_repair_replaces_newer_builds(self):
        self.fresh()
        edit_row(self.data, "randomizer", version="9.0.0")
        kinds = {c.id: c.kind for c in core.plan(self.bundle, modtool.read_registry(self.data / "mods"), force=True)}
        self.assertEqual(kinds["randomizer"], "downgrade")
        self.assertEqual(kinds["unlock_all"], "reinstall")
        core.install_set(self.data, self.bundle, {}, force=True)
        self.assertEqual(rows_of(self.data)["randomizer"]["version"], self.bundle["randomizer"]["manifest"]["version"])

    def test_failed_install_keeps_registry_consistent(self):
        add_row(self.data, "squatter", "1.0.0", extra={"install_dir": "packages/unlock_all/inner"})
        with self.assertRaises(core.ToolError):
            self.fresh()
        rows = rows_of(self.data)
        self.assertNotIn("unlock_all", rows)
        self.assertIn("coop_solo", rows)               # installed before the failure, and registered
        for mid, r in rows.items():
            self.assertTrue((self.data / "mods" / r["manifest"]["install_dir"]).is_dir(), mid)

    def test_refuses_while_game_runs(self):
        core.process_running = lambda name=core.PROCESS: True
        with self.assertRaises(core.ToolError):
            self.fresh()
        self.assertFalse((self.data / "mods" / "installed.toml").exists())

    def test_install_folder(self):
        self.fresh()
        folder = self.tmp / "dev"
        folder.mkdir()
        shutil.copy2(RELEASE / f"unlock_all-{self.bundle['unlock_all']['manifest']['version']}.tar.xz", folder)
        result = core.install_folder(self.data, folder, {})
        self.assertEqual([(c.id, c.kind) for c in result.changes], [("unlock_all", "reinstall")])
        with self.assertRaises(core.ToolError):
            core.install_folder(self.data, self.tmp / "dev-empty-missing", {})

    # ---------------------------------------------------------------- switches
    def views(self, prefs=None):
        rows = modtool.read_registry(self.data / "mods") if (self.data / "mods" / "installed.toml").exists() else []
        return {v.tile.key: v for v in core.build_views(self.bundle, rows, prefs or {})}

    def test_views_before_and_after_install(self):
        before = self.views()
        self.assertEqual(list(before), [t.key for t in core.KNOWN_TILES])
        self.assertTrue(all(v.status == "missing" for v in before.values()))
        self.assertFalse(before["mksmk_probe"].on)
        self.assertEqual(before["ldk"].levels, ["x2", "x3", "x4"])
        self.assertEqual(before["ldk"].level, "x3")
        self.fresh()
        after = self.views()
        self.assertTrue(all(v.status == "ok" for v in after.values()), {k: v.status for k, v in after.items()})
        self.assertTrue(after["ldk"].on)
        self.assertEqual(after["ldk"].level, "x3")
        self.assertEqual(after["mk_upgrade"].tag, "Preview")
        self.assertEqual(after["mksmk_probe"].tag, "Diagnostics")
        self.assertEqual(after["ldk"].tag, "Stable")

    def test_switches_apply_at_once(self):
        self.fresh()
        v = self.views()
        core.switch_tile(self.data, v["time_rifts"], False)
        self.assertFalse(rows_of(self.data)["time_rifts"]["enabled"])
        core.switch_tile(self.data, v["ldk"], True, level="x4")
        rows = rows_of(self.data)
        self.assertEqual([m for m in core.LDK_IDS if rows[m]["enabled"]], ["ldk_x4"])
        self.assertEqual(self.views()["ldk"].level, "x4")
        core.switch_tile(self.data, self.views()["ldk"], False)
        self.assertFalse(any(rows_of(self.data)[m]["enabled"] for m in core.LDK_IDS))
        self.assertFalse(self.views()["ldk"].on)

    def test_routine_limit_blocks_switching_on_but_not_off(self):
        self.fresh()
        add_row(self.data, "big_dev_mod", "1.0.0", routines=30)
        v = self.views()
        with self.assertRaises(core.ToolError) as caught:
            core.switch_tile(self.data, v["mksmk_probe"], True)
        self.assertIn(str(core.ROUTINE_LIMIT), str(caught.exception))
        self.assertFalse(rows_of(self.data)["mksmk_probe"]["enabled"])
        core.switch(self.data, {"big_dev_mod": False})
        core.switch_tile(self.data, self.views()["mksmk_probe"], True)
        self.assertTrue(rows_of(self.data)["mksmk_probe"]["enabled"])

    def test_not_installed_tile_cannot_switch(self):
        with self.assertRaises(core.ToolError):
            core.switch_tile(self.data, self.views()["unlock_all"], False)


if __name__ == "__main__":
    unittest.main()
