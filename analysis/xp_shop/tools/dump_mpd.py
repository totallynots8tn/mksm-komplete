"""Dump the pause-menu move-purchase database ("M&PD", GAMEDATA.WAD record 713)
as a CSV, resolving node text CRCs through record 714 (the text-CRC index that
parallels text table record 156).

Read-only. Reads the ISO through analysis/xbox_roster/tools/pwf.py and the text
dump analysis/upgrade_design/out/text_game.csv. Writes analysis/xp_shop/out/.

Node layout (0x30-byte header, then child ids), from MPDatabase::ImportData
0x9E8F0 and the walkers it calls:
  +0x00 id (CRC)          +0x04 type: 3 root(character) 2 category 1 group 0 leaf
  +0x0C child count       +0x10 parent id (pointer after import)
  +0x18 name text CRC     +0x1C description text CRC (text index after import)
  +0x20 WAD CRC (leaf)    +0x24 level (leaf with +0x20) or WAD CRC
  +0x28 XP cost           +0x2C owned/default flag
Roots carry the character id at +0x18 (0 Liu Kang, 1 Kung Lao, 0x58 Sub-Zero,
0x52 Scorpion) and are skipped by the CRC conversion.
"""
import csv
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.normpath(os.path.join(HERE, "..", "out"))
sys.path.insert(0, os.path.join(ROOT, "analysis", "xbox_roster", "tools"))

import pwf  # noqa: E402  (opens the ISO on import)

MPD_RECORD = 713
TEXT_CRC_RECORD = 714
CHARACTERS = {0: "Liu Kang", 1: "Kung Lao", 0x58: "Sub-Zero", 0x52: "Scorpion"}
SPECIALS, COMBOS = 461, 463          # category text indices (0x1CD, 0x1CF)
APPLY_SLOT = {466: 0, 467: 2, 468: 1, 469: 3}   # 0x9B410 jump table


def load_text():
    path = os.path.join(ROOT, "analysis", "upgrade_design", "out", "text_game.csv")
    with open(path, encoding="utf-8") as f:
        return {int(r["index"]): r["text"] for r in csv.DictReader(f)}


def parse(blob):
    assert blob[:4] == b"M&PD", blob[:4]
    count, roots = struct.unpack_from("<II", blob, 8)
    root_ids = struct.unpack_from("<%dI" % roots, blob, 0x20)
    nodes, cursor = [], 0x20 + roots * 4
    while len(nodes) < count:
        f = struct.unpack_from("<12I", blob, cursor)
        children = struct.unpack_from("<%dI" % f[3], blob, cursor + 0x30)
        nodes.append({"offset": cursor, "f": f, "children": children})
        cursor += 0x30 + f[3] * 4
    assert cursor == len(blob), (hex(cursor), hex(len(blob)))
    return root_ids, nodes


def main():
    blob = pwf.decoded(MPD_RECORD)
    crcs = struct.unpack("<%dI" % (len(pwf.decoded(TEXT_CRC_RECORD)) // 4), pwf.decoded(TEXT_CRC_RECORD))
    text_of_crc = {c: i for i, c in enumerate(crcs)}
    text = load_text()
    root_ids, nodes = parse(blob)
    by_id = {n["f"][0]: k for k, n in enumerate(nodes)}

    def tindex(crc):
        return text_of_crc.get(crc, -1) if crc not in (0, 0xFFFFFFFF) else -1

    rows = []

    def walk(k, char, category, group, slot_base):
        n = nodes[k]
        f = n["f"]
        name, desc = tindex(f[6]), tindex(f[7])
        if f[1] == 2 or (f[1] == 1 and category is None):
            category = name
        elif f[1] == 1:
            group = name
        slot = ""
        if f[1] == 0 and category == SPECIALS and group is not None:
            slot = slot_base
        elif f[1] == 0 and category == COMBOS:
            parent = nodes[by_id[f[4]]]
            slot = 13 + parent["children"].index(f[0])
        if f[1] == 0:
            rows.append({
                "node": k, "offset": "0x%04X" % n["offset"], "character": CHARACTERS.get(char, char),
                "category": text.get(category, ""), "group": text.get(group, "") if group else "",
                "name_index": name, "name": text.get(name, "").split("\n")[0],
                "desc_index": desc, "desc": text.get(desc, "").split("\n")[0],
                "level": f[9] if f[8] not in (0, 0xFFFFFFFF) else "",
                "cost": "" if f[10] == 0xFFFFFFFF else f[10], "default_owned": f[11],
                "purchase_slot": slot,
                "apply_slot": APPLY_SLOT.get(group, "") if category == SPECIALS else slot,
                "raw": " ".join("%08x" % v for v in f),
            })
        for position, child in enumerate(n["children"]):
            child_k = by_id[child]
            base = slot_base
            if f[1] == 2 and name == SPECIALS:
                base = position    # Purchase_special: index of the group in Specials
            walk(child_k, char, category, group, base)

    for root in root_ids:
        k = by_id[root]
        walk(k, nodes[k]["f"][6], None, None, None)

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "mpd_tree.csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(f"{len(nodes)} nodes, {len(rows)} leaves -> {path}")


if __name__ == "__main__":
    main()
