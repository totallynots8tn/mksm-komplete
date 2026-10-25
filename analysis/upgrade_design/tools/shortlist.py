"""Build out/repurpose_shortlist.csv: categorize text-table entries that are
candidates to re-purpose for Extended Upgrades options/perks. Read-only."""
import csv, os, collections
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "out"))
rows = []
with open(os.path.join(OUT, "text_game.csv"), newline="", encoding="utf-8") as f:
    for x in csv.DictReader(f):
        x["index"] = int(x["index"]); rows.append(x)
by = {r["index"]: r for r in rows}

cats = []  # (category, index, note)
def add(cat, idx, note=""):
    if idx in by: cats.append((cat, idx, note))

# 1. Combo-rank popup words (keyed by hash) 1640-1659; 'Impossible' dup x3
for i in range(1640, 1660):
    add("combo_popup_word", i, "keyed toast word; combo-rank popup")
# 2. Duplicate 'Impossible' (same key 3d85cdbc at 1657/1658/1659)
for i in (1658, 1659):
    add("duplicate_key", i, "same hash key as 1657 'Impossible' -> redundant")
# 3. Debug / internal menu labels 1603-1639 (Main Menu, Camera, ability toggles, God Mode)
for i in range(1603, 1640):
    add("debug_menu_label", i, "internal debug/cheat menu text; likely unused in retail")
# 4. Platform ability names 1613-1620
for i in range(1613, 1621):
    add("ability_name", i, "platform-ability upgrade name (also in debug list)")
# 5. Fatality Level menu 1632-1637 (real VS menu with 0-3 levels)
for i in range(1632, 1638):
    add("fatality_level_menu", i, "VS 'Fatality Level' selector; 4 levels + P1/P2 headers")
# 6. Upgrade-menu chrome 396-465
for i in list(range(396, 412)) + list(range(425, 466)):
    add("upgrade_menu_chrome", i, "pause-menu Moves/Purchase/Info chrome + state strings")
# 7. Upgrade description format strings 470-481
for i in range(470, 482):
    add("upgrade_fmt_string", i, "'%s\\n\\n<Special> %d level Up %d' purchase descriptions")
# 8. (PH) unused move-description placeholders
ph = [r["index"] for r in rows if "(PH)" in r["text"]]
for i in ph:
    add("ph_move_placeholder", i, "UNUSED move-list slot; already wired into Moves menu")
# 9. 'NA' filler (172 of them) - sample first 20
na = [r["index"] for r in rows if r["text"] == "NA"][:20]
for i in na:
    add("na_filler", i, "'NA' filler move slot (172 total)")
# 10. Ability-gained / Obtained keyed toasts (template for perk-unlock popup)
for i in (50, 74, 84, 88, 91, 98, 100, 108, 109, 138, 407, 352):
    add("ability_toast", i, "keyed 'ability gained/obtained' popup; perk-unlock template")

# de-dupe preserve order
seen = set(); out = []
for c, i, n in cats:
    if (c, i) in seen: continue
    seen.add((c, i)); out.append((c, i, n))

path = os.path.join(OUT, "repurpose_shortlist.csv")
with open(path, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["category", "index", "key", "len", "text", "note"])
    for c, i, n in sorted(out, key=lambda t: (t[0], t[1])):
        r = by[i]
        w.writerow([c, i, r["key"], len(r["text"]), r["text"].replace("\n", "\\n"), n])
cnt = collections.Counter(c for c, _, _ in out)
print(f"wrote {len(out)} shortlist rows -> {path}")
for c, n in cnt.most_common(): print(f"  {c}: {n}")
print(f"\n(PH) placeholders total: {len(ph)}  range {min(ph)}..{max(ph)}")
print(f"'NA' filler total: {sum(1 for r in rows if r['text']=='NA')}")
