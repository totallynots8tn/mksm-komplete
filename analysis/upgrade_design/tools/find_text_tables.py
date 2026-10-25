"""Locate the game/system text tables in GAMEDATA.WAD by EWDF stamp, decode
them with the language-pack decoder, and dump CSVs.

Read-only: imports analysis/xbox_roster/tools/pwf.py (which reads the ISO via
xiso.py). decode_text_table() is copied VERBATIM from
ShaolinMonksRecomp-0.2.0/tools/prepare_language_pack.py (cited in DESIGN.md).
Writes only inside analysis/upgrade_design/out/.
"""
import sys, os, csv, struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROSTER_TOOLS = os.path.normpath(os.path.join(HERE, "..", "..", "xbox_roster", "tools"))
OUT = os.path.normpath(os.path.join(HERE, "..", "out"))
sys.path.insert(0, ROSTER_TOOLS)

import pwf  # noqa: E402  (instantiate-on-import: opens ISO, reads WAD dir)

GAME_STAMP = 0xB3F9F220   # from language-pack source: "b3f9f220_h.bin" game text table
SYSTEM_RECORD = 158       # per task + prepare_language_pack.py (xbox_system_english.bin)


def decode_text_table(data: bytes):
    """VERBATIM copy of prepare_language_pack.decode_text_table()."""
    if len(data) < 4:
        raise ValueError("The text table has no count")
    count = struct.unpack_from("<I", data)[0]
    if count > (len(data) - 4) // 9:
        raise ValueError("The text table count exceeds its data")
    entries, cursor = [], 4
    for index in range(count):
        if cursor + 8 > len(data):
            raise ValueError(f"Truncated text entry {index}")
        key, length = struct.unpack_from("<II", data, cursor)
        cursor += 8
        if not length or cursor + length > len(data):
            raise ValueError(f"Invalid text length at entry {index}")
        value = data[cursor:cursor + length]
        if value[-1] != 0 or b"\0" in value[:-1]:
            raise ValueError(f"Invalid text terminator at entry {index}")
        entries.append({"id": index, "key": f"{key:08x}", "text": value[:-1].decode("cp1252")})
        cursor += length
    if cursor != len(data):
        raise ValueError("Unexpected trailing text-table data")
    return entries


def stamp_of(r):
    p, size = pwf.read(r, 512)
    if p[:4] == b"EWDF" and len(p) >= 17:
        length, payload, stamp = struct.unpack_from("<III", p, 4)
        return stamp, p[16:payload - 1].decode("ascii", "replace")
    return None, None


def main():
    print(f"WAD records: {pwf.COUNT}  stride: {pwf.STRIDE}")
    hits = []
    for r in range(pwf.COUNT):
        st, nm = stamp_of(r)
        if st == GAME_STAMP:
            hits.append((r, nm))
    print(f"records with stamp {GAME_STAMP:08x}: {hits}")
    # System record name
    print(f"record {SYSTEM_RECORD} name: {pwf.name(SYSTEM_RECORD)[0]}")
    return hits


if __name__ == "__main__":
    main()
