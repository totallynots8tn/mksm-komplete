"""Decode the game text table (record 156) and system text table (record 158)
and write full CSVs (index,key,text) to out/. Read-only on the ISO."""
import sys, os, csv
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "xbox_roster", "tools")))
sys.path.insert(0, HERE)
import pwf
from find_text_tables import decode_text_table

OUT = os.path.normpath(os.path.join(HERE, "..", "out"))

def dump(record, label):
    raw = pwf.decoded(record)
    entries = decode_text_table(raw)
    path = os.path.join(OUT, f"text_{label}.csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["index", "key", "text"])
        for e in entries:
            w.writerow([e["id"], e["key"], e["text"]])
    print(f"record {record} ({label}): {len(entries)} entries, {len(raw)} bytes -> {path}")
    return entries

game = dump(156, "game")
system = dump(158, "system")
print("\n--- system table (all) ---")
for e in system:
    print(f"  [{e['id']}] {e['key']}  {e['text']!r}")
print(f"\ngame table entry count: {len(game)}")
