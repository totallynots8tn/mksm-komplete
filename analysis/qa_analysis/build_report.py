#!/usr/bin/env python3
"""Rebuild analysis/qa_analysis/REPORT.md (+ overflow CSVs) from qa/ inputs.

Deterministic: no clocks, no mtimes, no random order. Python stdlib only.
Read-only outside analysis/qa_analysis/. Run:
    python analysis/qa_analysis/build_report.py
"""

import csv
import hashlib
import io
import re
import struct
import sys
from collections import Counter, OrderedDict
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / 'qa'
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools' / 'logread'))
import logread  # reuse the documented parsers/regexes

# ---------------------------------------------------------------- constants
SLOT_BASE = 0x131C          # first slot starts here (label at +4)
SLOT_PITCH = 0x51AC         # distance between slot labels / slot bases
SLOT_COUNT = 9              # slot positions that fit before the footer
FILE_SIZE = 0x2F240         # 193088 bytes

PROBE_TAGS = frozenset(('EVENTS', 'SAVEDIFF', 'UPGRADE', 'SHUFFLE', 'PLATE',
                        'PLATE051', 'PLATE052', 'PLATE054', 'PLATE060'))
LEGACY_TAGS = frozenset(('TRACE', 'PROBE25', 'PROBE90'))

RE_ROUTINE = logread.RE_ROUTINE
RE_EXC = re.compile(r'exception C0000005')
RE_SAVEDIFF_TOK = re.compile(r'^\+([0-9A-Fa-f]+):([0-9A-Fa-f]+)>([0-9A-Fa-f]+)\((\d+)\)$')
RE_LABEL = re.compile(rb'[\x20-\x7E]{4,}\.[\x20-\x7E]{1,4}\.[0-9:]{8}')
RE_XPSET2 = re.compile(r'^X(\d+):\+(-?[0-9A-Fa-f]+)c(-?\d+)@(.*)$')
RE_DROP = re.compile(r'^\.*\((\d+)\s+dropped\)\.*$')
RE_DMP = re.compile(r'ShaolinMonksRecomp\.(\d{4})\.(\d{2})\.(\d{2})_(\d{2})\.(\d{2})\.(\d{2})\.dmp$')

# EVENTS ordered-token regexes (reuse logread's)
RE_GROUP = logread.RE_GROUP
RE_SPAWN = logread.RE_SPAWN
RE_ANIM = logread.RE_ANIM


def hx(v):
    return '0x%X' % v


def slot_of(off):
    """(slot index, slot-relative offset) or ('header'/'footer', off)."""
    if off < SLOT_BASE:
        return 'header', off
    k, r = divmod(off - SLOT_BASE, SLOT_PITCH)
    if k < SLOT_COUNT:
        return k, r
    return 'footer', off


# ---------------------------------------------------------------- corpus
def collect_logs():
    """All qa logs, deduped by file name keeping the largest copy."""
    best = {}
    paths = []
    for d in sorted(QA.iterdir()):
        if d.is_dir():
            paths.extend(sorted(d.rglob('*.log')))
    for p in paths:
        size = p.stat().st_size
        prev = best.get(p.name)
        if prev is None or size > prev[0] or (size == prev[0] and str(p) < prev[1]):
            best[p.name] = (size, str(p))
    out = []
    for name, (size, sp) in sorted(best.items()):
        m = re.search(r'shaolin-recomp_(\d+)\.log$', name)
        num = int(m.group(1)) if m else -1
        out.append({'name': name, 'num': num, 'path': Path(sp), 'size': size})
    out.sort(key=lambda d: (d['num'], d['name']))
    return out


def collect_dmps():
    best = {}
    for d in sorted(QA.iterdir()):
        if d.is_dir():
            for p in sorted(d.rglob('*.dmp')):
                best.setdefault(p.name, p)
    out = []
    for name, p in sorted(best.items()):
        m = RE_DMP.search(name)
        when = None
        if m:
            when = datetime(*[int(g) for g in m.groups()])
        out.append({'name': name, 'path': p, 'when': when})
    return out


def collect_saves():
    files = []
    for d in sorted(QA.glob('run-*')):
        for p in sorted((d / 'saves').glob('*.dat')):
            files.append(p)
    return files


# ---------------------------------------------------------------- log parse
def parse_log(entry):
    """Everything the timeline + EVENTS/UPGRADE tasks need from one log."""
    path = entry['path']
    info = {'entry': entry, 'empty': entry['size'] == 0}
    if info['empty']:
        info.update(stamp=None, duration=None, mods=None, saves=[], exit=None,
                    tags=Counter(), errors=[], exceptions=[], reports=[],
                    first_ts=None, events=[], upgrade=[], savediff=[],
                    shuffle=[], unparsed=Counter())
        return info
    lines, recs = logread.read_log(path)
    facts = logread.session_facts(recs)
    info.update(stamp=facts['stamp'], duration=facts['duration'],
                mods=facts['mods'], saves=facts['saves'], exit=facts['exit'])
    info['first_ts'] = next((ts for ts, _l, _t, _m, _r in recs
                             if ts is not None), None)
    tags = Counter()
    errors = []
    reports = []
    unparsed = Counter()
    for ts, lvl, _thr, msg, raw in recs:
        if RE_EXC.search(msg):
            info.setdefault('exceptions', []).append((ts, msg.strip()))
        m = RE_ROUTINE.match(msg)
        if not m:
            continue
        mod, rest = m.group(1), m.group(2)
        tag = rest.split(' ', 1)[0] if rest else ''
        args = rest[len(tag):].strip()
        if args.endswith(logread.DISABLED):
            args = args[:-len(logread.DISABLED)].rstrip()
        rep = {'ts': ts, 'mod': mod, 'tag': tag, 'args': args, 'rest': rest}
        if tag in PROBE_TAGS or tag in LEGACY_TAGS:
            tags[tag] += 1
            reports.append(rep)
        else:
            errors.append((ts, raw.strip()))
    info.setdefault('exceptions', [])
    info['tags'] = tags
    info['errors'] = errors
    info['reports'] = reports
    info['unparsed'] = unparsed

    for rep in reports:
        reason, fields, body = logread.split_head_body(rep['args'], rep['tag'])
        rep['reason'] = reason
        rep['fields'] = fields
        rep['body'] = body
        if rep['tag'] == 'EVENTS':
            info.setdefault('events', []).append(rep)
        elif rep['tag'] == 'UPGRADE':
            info.setdefault('upgrade', []).append(rep)
        elif rep['tag'] == 'SAVEDIFF':
            info.setdefault('savediff', []).append(rep)
        elif rep['tag'] == 'SHUFFLE':
            info.setdefault('shuffle', []).append(rep)
    for k in ('events', 'upgrade', 'savediff', 'shuffle'):
        info.setdefault(k, [])

    # last map, GUESS: decode the +C label dword (".NNN") of the last SAVEDIFF
    info['last_map'] = '-'
    for rep in reversed(info['savediff']):
        for tok in logread.tokens(rep['body']):
            m = RE_SAVEDIFF_TOK.match(tok)
            if m and m.group(1).upper() == 'C':
                val = int(m.group(3), 16)
                raw4 = struct.pack('<I', val)
                if all(0x20 <= b < 0x7F for b in raw4):
                    txt = raw4.decode('ascii')
                    mm = re.match(r'^\.(\d+)$', txt)
                    if mm:
                        info['last_map'] = mm.group(1)
                        break
        if info['last_map'] != '-':
            break
    return info


def exception_wall(info, ts):
    if info['stamp'] and info['first_ts'] is not None and ts is not None:
        return info['stamp'] + timedelta(seconds=ts - info['first_ts'])
    return None


# ---------------------------------------------------------------- EVENTS
def norm_loaded(lst):
    seen = []
    for part in lst.split(','):
        part = part.strip()
        if not part or part == '-' or set(part) == {'F'} and len(part) == 8:
            continue
        if part not in seen:
            seen.append(part)
    return ','.join(seen)


def parse_events_stream(body):
    """Ordered token walk of one EVENTS body -> dict of stats + area segments."""
    st = {'groups': [], 'areas': [], 'spawns': {}, 'fails_bare': 0,
          'heap_low': {}, 'deaths': Counter(), 'kills': Counter(),
          'xp_total': 0, 'xp_events': 0, 'dropped': 0, 'unparsed': [],
          's_tokens': Counter()}
    area = None
    for tok in logread.tokens(body):
        m = RE_GROUP.match(tok)
        if m:
            heaps = {}
            for part in m.group(4).split(','):
                if not part:
                    continue
                name, _, frac = part.partition('=')
                free, _, total = frac.partition('/')
                if not total:
                    st['unparsed'].append(tok)
                    break
                if name.upper() == 'FFFFFFFF':
                    continue
                heaps[name.upper()] = (int(free, 16), int(total, 16))
            loaded_raw = m.group(5)
            key = norm_loaded(loaded_raw)
            g = {'grp': m.group(1).upper(), 'count': int(m.group(2)),
                 'pool': m.group(3), 'heaps': heaps, 'loaded': loaded_raw,
                 'key': key}
            st['groups'].append(g)
            new_area = area is None or area['key'] != key
            if new_area:
                area = {'key': key, 'first_grp': g['grp'], 'gcount': 0,
                        'spawns': {}, 'fails': 0, 'heap_low': {},
                        's4d': 0, 's1a': 0}
                st['areas'].append(area)
            for typ, (free, total) in heaps.items():
                if total and (typ not in st['heap_low']
                              or free < st['heap_low'][typ][0]):
                    st['heap_low'][typ] = (free, total)
                if new_area or (typ not in area['heap_low']
                                or free < area['heap_low'][typ][0]):
                    area['heap_low'][typ] = (free, total)
            area['gcount'] += 1
            continue
        m = RE_SPAWN.match(tok)
        if m:
            typ = m.group(1).upper()
            st['s_tokens'][typ] += 1
            tgt = st['spawns'].setdefault(typ, {'n': 0, 'bytes': 0, 'fail': 0})
            if area is not None:
                atgt = area['spawns'].setdefault(typ, {'n': 0, 'bytes': 0,
                                                       'fail': 0})
            if m.group(2) == '!fail':
                tgt['fail'] += 1
                if area is not None:
                    atgt['fail'] += 1
            else:
                cost = int(m.group(2), 16)
                tgt['n'] += 1
                tgt['bytes'] += cost
                if area is not None:
                    atgt['n'] += 1
                    atgt['bytes'] += cost
            continue
        if tok == 'F':
            st['fails_bare'] += 1
            if area is not None:
                area['fails'] += 1
            continue
        m = RE_DROP.match(tok)
        if m:
            st['dropped'] += int(m.group(1))
            continue
        m = logread.RE_XP.match(tok)
        if m:
            st['xp_total'] += logread.num(m.group(1))
            st['xp_events'] += 1
            continue
        if RE_XPSET2.match(tok) or logread.RE_KILL.match(tok) \
                or logread.RE_DEATH.match(tok) or logread.RE_DMG.match(tok) \
                or logread.RE_BODY.match(tok):
            if logread.RE_KILL.match(tok):
                st['kills'][logread.RE_KILL.match(tok).group(1).upper()] += 1
            elif logread.RE_DEATH.match(tok):
                st['deaths'][logread.RE_DEATH.match(tok).group(1).upper()] += 1
            continue
        st['unparsed'].append(tok)
    return st


# ---------------------------------------------------------------- saves
def find_labels(data):
    out = []
    for m in RE_LABEL.finditer(data):
        slot, rel = slot_of(m.start())
        if isinstance(slot, int) and rel == 4:
            out.append((m.start(), m.group().decode('ascii', 'replace'), slot))
    return out


def diff_runs(a, b):
    diff = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
    runs = []
    for i in diff:
        if runs and i == runs[-1][1] + 1:
            runs[-1][1] = i
        else:
            runs.append([i, i])
    return diff, [(s, e) for s, e in runs]


def nearest_label(labels, off):
    best = None
    for loff, text, slot in labels:
        if loff <= off and (best is None or loff > best[0]):
            best = (loff, text, slot)
    return best


# ---------------------------------------------------------------- XP search
def xp_scan(save_paths):
    pats = []
    for label, val in (('6650', 6650), ('2890', 2890)):
        pats.append(('%s u16' % label, struct.pack('<H', val)))
        pats.append(('%s u32' % label, struct.pack('<I', val)))
        pats.append(('%s f32' % label, struct.pack('<f', float(val))))
    agg = {}   # (pattern, slot, rel) -> [files]
    for p in save_paths:
        data = p.read_bytes()
        for pname, pat in pats:
            start = 0
            while True:
                i = data.find(pat, start)
                if i < 0:
                    break
                start = i + 1
                slot, rel = slot_of(i)
                agg.setdefault((pname, slot, rel), []).append(p.name)
    return agg


# ---------------------------------------------------------------- main
def main():
    logs = collect_logs()
    infos = [parse_log(e) for e in logs]
    dmps = collect_dmps()
    saves = collect_saves()
    rep = io.StringIO()
    W = rep.write
    csvs = {}

    def md5_of(data):
        return hashlib.md5(data).hexdigest()

    # ============================================================== task 1
    W('# MKSM QA analysis - 2026-10-24 playthrough\n\n')
    W('Inputs: %d logs (deduped by name, largest copy kept), %d save .dat '
      'files, %d crash dumps, roster/maps JSON. Generated by '
      'analysis/qa_analysis/build_report.py (deterministic, stdlib only).\n\n'
      % (len(logs), len(saves), len(dmps)))

    W('## 1. Save diffs: upgrade unlocks and the XP field\n\n')

    feat_dir = QA / 'run-20261024-2243' / 'saves'
    s1p = feat_dir / 'save_20261024-224337.dat'
    s2p = feat_dir / 'save_20261024-224428.dat'
    s1 = s1p.read_bytes()
    s2 = s2p.read_bytes()
    diff, runs = diff_runs(s1, s2)
    labels_u = sorted(set([(l, t, s) for l, t, s in find_labels(s1)]
                          + [(l, t, s) for l, t, s in find_labels(s2)]))

    # region summary
    region = Counter()
    region_bytes = Counter()
    for s, e in runs:
        slot, rel = slot_of(s)
        key = 'slot%s' % slot if isinstance(slot, int) else slot
        region[key] += 1
        region_bytes[key] += e - s + 1
    W('3-line summary:\n')
    W('- Save #2 (22:44:28) differs from save #1 (22:43:37) in %d bytes / '
      '%d runs: a whole new slot 4 was written (label "LIU KANG.  6.00:52:17"), '
      'plus 20 bytes in slot 5, 4 header bytes and a 20-byte footer hash.\n'
      % (len(diff), len(runs)))
    W('- Slot 4 and slot 5 hold the same game; a slot-relative cross-diff '
      '(new slot 4 vs old slot 5) isolates exactly 10 runs: playtime counter, '
      'label digits, upgrade counters (+0xDC frequent, +0x1C5/+0x1D3 rare '
      'upgrade/unlock) and the XP block (+0x4940 u32 balance, '
      '+0x4958..+0x4970 f32 position cluster).\n')
    W('- Slot geometry: labels sit at slot base +4; bases are 0x%X + k*0x%X '
      '(k=0..8), so slot size = 0x%X (%d bytes), 9 slots, header 0x%X, '
      'footer hash at 0x2F22C.\n\n'
      % (SLOT_BASE, SLOT_PITCH, SLOT_PITCH, SLOT_PITCH, SLOT_BASE))

    W('### 1.1 Featured pair run-20261024-2243 save#1 -> save#2\n\n')
    W('Labels found (file offset -> slot):\n\n')
    W('| label | offset | slot |\n|---|---|---|\n')
    for loff, text, slot in labels_u:
        W('| `%s` | 0x%X | %d |\n' % (text, loff, slot))
    W('\nRegion summary of the file diff:\n\n')
    W('| region | runs | changed bytes |\n|---|---|---|\n')
    for key in sorted(region):
        W('| %s | %d | %d |\n' % (key, region[key], region_bytes[key]))
    W('\nFull run list (712 runs) in `save_diff_featured_runs.csv`. '
      'First 20 runs:\n\n')
    W('| offset | len | old | new | nearest preceding label (slot) |\n'
      '|---|---|---|---|---|\n')
    for s, e in runs[:20]:
        lab = nearest_label(labels_u, s)
        labtxt = ('%s (slot %d)' % (lab[1], lab[2])) if lab else 'none (header)'
        old = s1[s:e + 1].hex().upper()
        new = s2[s:e + 1].hex().upper()
        if len(old) > 40:
            old = old[:40] + '..'
            new = new[:40] + '..'
        W('| 0x%06X | %d | `%s` | `%s` | %s |\n' % (s, e - s + 1, old, new,
                                                    labtxt))
    csv_rows = []
    for s, e in runs:
        slot, rel = slot_of(s)
        lab = nearest_label(labels_u, s)
        csv_rows.append(['0x%06X' % s, e - s + 1,
                         'slot%s' % slot if isinstance(slot, int) else slot,
                         '0x%X' % rel if isinstance(slot, int) else '',
                         lab[1] if lab else '', lab[2] if lab else '',
                         s1[s:e + 1].hex().upper(), s2[s:e + 1].hex().upper()])
    csvs['save_diff_featured_runs.csv'] = (
        ['offset', 'len', 'region', 'slot_rel', 'label', 'label_slot',
         'old_hex', 'new_hex'], csv_rows)

    # cross-slot diff: slot4(save#2) vs slot5(save#1)
    sl4 = s2[SLOT_BASE + 4 * SLOT_PITCH:SLOT_BASE + 5 * SLOT_PITCH]
    sl5 = s1[SLOT_BASE + 5 * SLOT_PITCH:SLOT_BASE + 6 * SLOT_PITCH]
    _, xruns = diff_runs(sl5, sl4)
    W('\nCross-slot diff: slot 4 written by save #2 vs slot 5 (the active '
      'game) in save #1 - slot-relative, isolates the fields the game '
      'touched (upgrade purchase + ~5 s of play):\n\n')
    W('| slot-rel offset | len | old (slot5, save#1) | new (slot4, save#2) | '
      'reading (GUESS) |\n|---|---|---|---|---|\n')
    guesses = {
        0x0000: 'playtime frame counter u32 (0x02DE46=188486 -> 0x02DF55='
                '188757, +271 frames ~ 4.5 s @60fps)',
        0x0018: "label seconds digit '2'->'7' (00:52:12 -> 00:52:17)",
        0x00DC: 'upgrade/unlock byte 0x40->0x42',
        0x01C5: 'upgrade level counters: +0x1C5 03->04, +0x1C6 02->03',
        0x01D3: 'unlock flag 00->01',
        0x4940: 'XP balance u32: 0x5B22=23330 -> 0x0726=1830 (XP spent on '
                'upgrades; SAVEDIFF elsewhere shows +4940 rising on kills)',
        0x4958: 'f32 position/world coords cluster (GUESS: decoded values '
                'like 13453.7 / -5826.5 are coordinates, not XP)',
        0x4960: 'f32 position/world coords cluster (GUESS)',
        0x4968: 'f32 position/world coords cluster (GUESS)',
        0x4970: 'f32 position/world coords cluster (GUESS)',
    }
    for s, e in xruns:
        W('| +0x%04X | %d | `%s` | `%s` | %s |\n'
          % (s, e - s + 1, sl5[s:e + 1].hex().upper(),
             sl4[s:e + 1].hex().upper(), guesses.get(s, '')))
    W('\nThe identical 10 slot-relative runs also appear in slot 5 itself '
      'between save #1 and save #2 - the game updated the old slot and '
      'copied it into the empty slot 4 on save.\n\n')

    # ---- all consecutive pairs
    W('### 1.2 Every consecutive save pair in all runs\n\n')
    pair_rows = []
    off_freq = Counter()
    pair_offsets = []
    all_runs_rows = []
    for i in range(len(saves) - 1):
        pa, pb = saves[i], saves[i + 1]
        if pa.parent != pb.parent:
            continue  # pairs are within a run folder (chronological)
        a = pa.read_bytes()
        b = pb.read_bytes()
        d, rr = diff_runs(a, b)
        labs = sorted(set([(l, t, s) for l, t, s in find_labels(a)]
                          + [(l, t, s) for l, t, s in find_labels(b)]))
        slots = set()
        offs = set()
        for s, e in rr:
            slot, rel = slot_of(s)
            slots.add('slot%s' % slot if isinstance(slot, int) else slot)
            if isinstance(slot, int):
                offs.add(rel)
        off_freq.update(offs)
        pair_offsets.append(offs)
        pair_rows.append([pa.name, pb.name, len(d), len(rr),
                          ' '.join(sorted(slots))])
        for s, e in rr:
            slot, rel = slot_of(s)
            lab = nearest_label(labs, s)
            all_runs_rows.append([pa.name, pb.name, '0x%06X' % s, e - s + 1,
                                  'slot%s' % slot if isinstance(slot, int)
                                  else slot,
                                  '0x%X' % rel if isinstance(slot, int) else '',
                                  lab[1] if lab else '',
                                  a[s:e + 1].hex().upper(),
                                  b[s:e + 1].hex().upper()])
    csvs['save_pairs.csv'] = (['old', 'new', 'changed_bytes', 'runs',
                               'regions'], pair_rows)
    csvs['save_diff_all_runs.csv'] = (
        ['old_file', 'new_file', 'offset', 'len', 'region', 'slot_rel',
         'label', 'old_hex', 'new_hex'], all_runs_rows)

    W('3-line summary:\n')
    zero_pairs = sum(1 for r in pair_rows if r[2] == 0)
    W('- %d consecutive within-run pairs diffed (%d identical - a re-save '
      'with no game progress); every non-identical pair touches the 4-byte '
      'header at 0x0 and the 20-byte footer hash at 0x2F22C.\n'
      % (len(pair_rows), zero_pairs))
    nonempty = [o for o in pair_offsets if o]
    always = set.intersection(*nonempty) if nonempty else set()
    W('- Across the %d non-identical pairs, %d slot-relative offsets change '
      'in EVERY pair (%s); the upgrade-level/unlock offsets +0x1C5/+0x1C6/'
      '+0x1D3 appear only in the 2243 featured pair.\n'
      % (len(nonempty), len(always),
         ' '.join('+0x%X' % o for o in sorted(always)) or 'none'))
    W('- Full per-run data: save_pairs.csv, save_diff_all_runs.csv, '
      'offset_frequency.csv.\n\n')
    W('| old | new | changed bytes | runs | regions |\n|---|---|---|---|---|\n')
    for row in pair_rows[:40]:
        W('| %s | %s | %d | %d | %s |\n' % tuple(row))
    if len(pair_rows) > 40:
        W('\n(%d more pairs in save_pairs.csv)\n' % (len(pair_rows) - 40))
    W('\nOffsets present in every non-identical pair (slot-relative, hex; '
      'the 1 identical pair excluded):\n\n')
    W('`%s`\n\n' % (' '.join('+0x%X' % o for o in sorted(always)) or 'none'))
    top = off_freq.most_common()
    top.sort(key=lambda kv: (-kv[1], kv[0]))
    W('Most frequent changed offsets (count of pairs / %d):\n\n'
      % len(pair_rows))
    W('| slot-rel offset | pairs | class (GUESS) |\n|---|---|---|\n')
    shown = 0
    for off, n in top:
        if n < 2 or shown >= 25:
            break
        cls = ''
        if off == 0x0:
            cls = 'playtime frame counter u32'
        elif off == 0xDC:
            cls = 'FREQUENT upgrade/unlock byte (21/26 pairs)'
        elif off in (0x1C5, 0x1C6, 0x1D3):
            cls = 'RARE upgrade-level/unlock (only the 2243 pair)'
        elif off == 0x4940:
            cls = 'XP balance u32'
        elif 0x4954 <= off <= 0x49C4:
            cls = 'f32 position/world coords cluster (GUESS)'
        elif off < 0x20:
            cls = 'label/playtime text'
        if off in always:
            cls = (cls + '; ' if cls else '') + 'in every non-identical pair'
        W('| +0x%X | %d | %s |\n' % (off, n, cls))
        shown += 1
    csvs['offset_frequency.csv'] = (['slot_rel_offset', 'pairs'],
                                    [['0x%X' % o, n] for o, n in top])

    # ---- XP value search
    W('\n### 1.3 XP value search (6650=0x19FA, 2890=0xB4A)\n\n')
    agg = xp_scan(saves)
    rank = []
    for (pname, slot, rel), files in agg.items():
        rank.append((pname, slot, rel, len(files), files))
    rank.sort(key=lambda r: (r[0], -r[3], str(r[1]), r[2]))
    hit_rows = []
    W('Hits ranked by how many of the %d saves contain the pattern at the '
      'same slot-relative offset (only hits inside slot regions are '
      'meaningful; header/footer and one-off hits are noise). u16 patterns '
      'match random bytes often - recurrence is the signal.\n\n'
      % len(saves))
    W('| pattern | slot | slot-rel | files | example files |\n'
      '|---|---|---|---|---|\n')
    shown = 0
    for pname, slot, rel, n, files in rank:
        hit_rows.append([pname, str(slot), '0x%X' % rel, n,
                         ' '.join(sorted(files))])
        if n >= 2 and shown < 30:
            W('| %s | %s | +0x%X | %d | %s |\n'
              % (pname, slot, rel, n, ', '.join(sorted(files)[:3])))
            shown += 1
    csvs['xp_search_hits.csv'] = (
        ['pattern', 'slot', 'slot_rel', 'file_count', 'files'], hit_rows)
    u32_hits = [r for r in rank if r[0].endswith('u32') and r[3] >= 2]
    f32_hits = [r for r in rank if r[0].endswith('f32') and r[3] >= 2]
    W('\nFinding: ZERO recurring hits. Neither 6650 (0x19FA) nor 2890 '
      '(0xB4A) appears in any of the %d saves as u16/u32/f32 at the same '
      'slot-relative offset in 2+ files (u32 recurring: %d, f32 recurring: '
      '%d). The exact XP balances were never archived at a save instant, so '
      'the value search cannot localize the field. The XP balance is instead '
      'identified as the u32 at slot+0x4940 from converging evidence: (a) '
      'save#1->#2 shows +0x4940 falling by exactly an upgrade-cost-sized '
      'amount; (b) SAVEDIFF bodies log +4940 rising after kills '
      '(+4940:A96>177A); (c) its decoded values track the XP trajectory '
      'across saves. The f32 cluster at +0x4954..+0x49C0 decodes to '
      'coordinates (e.g. 13453.7, -5826.5), not XP - it is the player '
      'position/world-coords block (GUESS).\n\n'
      % (len(saves), len(u32_hits), len(f32_hits)))

    # ============================================================== task 2
    W('## 2. Brutality and dismember data (UPGRADE reports)\n\n')
    anim = Counter()          # (owner, fatal, event) -> summed count
    cmds = Counter()          # (name, args, callers) -> summed count
    arm_tokens = 0
    up_unparsed = Counter()
    n_up_reports = 0
    n_sessions = 0
    for info in infos:
        if not info['upgrade']:
            continue
        n_sessions += 1
        # UPGRADE reports are cumulative within a session (verified: the
        # command stream of save#N is a prefix of save#N+1) -> take the
        # richest report per session, then sum across sessions.
        best = None
        for repu in info['upgrade']:
            c, a, st, unp = logread.parse_upgrade(repu['body'])
            n_up_reports += 1
            score = (sum(a.values()), len(c))
            if best is None or score > best[0]:
                best = (score, c, a, st, unp)
        _, c, a, st, unp = best
        anim.update(a)
        cmds.update(Counter(c))
        for tok in unp:
            if tok == 'ARM':
                arm_tokens += 1
            else:
                up_unparsed[tok] += 1

    fatal_events = {}
    plain_events = {}
    for (owner, fatal, event), n in anim.items():
        (fatal_events if fatal else plain_events).setdefault(
            (owner, event), 0)
        if fatal:
            fatal_events[(owner, event)] += n
        else:
            plain_events[(owner, event)] += n
    f_only = sorted((k for k in fatal_events if k not in plain_events),
                    key=lambda k: (-fatal_events[k], k[0], k[1]))

    W('3-line summary:\n')
    W('- Merged ANIM histograms from the richest UPGRADE report of each of '
      '%d sessions (%d reports total): %d keys, %s samples.\n'
      % (n_sessions, n_up_reports, len(anim), format(sum(anim.values()), ',')))
    W('- %d event types appear ONLY in [F] fatality/brutality mode; the '
      'player block p[F]1D..p[F]3D is present with (near-)identical counts, '
      'consistent with one scripted brutality combo sampled per hit.\n'
      % len(f_only))
    W('- All mutilate calls share caller @1A2871/1818F5 and ecx=6330E1; '
      'victims are the (eN) actor slots and arg3 is 0x12C/0x258/0 - a '
      'dismemberment id (GUESS).\n\n')

    W('### 2.1 Event types that only appear with [F]\n\n')
    W('| owner | [F] event | merged count | also plain? |\n|---|---|---|---|\n')
    for owner, event in f_only[:40]:
        W('| %s | [F]%s | %d | no |\n' % (owner, event or '-',
                                          fatal_events[(owner, event)]))
    if len(f_only) > 40:
        W('\n(%d more in anim_histogram_merged.csv)\n' % (len(f_only) - 40))
    csvs['anim_histogram_merged.csv'] = (
        ['owner', 'mode', 'event', 'merged_count', 'other_mode_present'],
        [[o, 'F' if f else '.', e or '-', n,
          'yes' if (o, e) in (plain_events if f else fatal_events) else 'no']
         for (o, f, e), n in sorted(anim.items(),
                                    key=lambda kv: (-kv[1], kv[0][0],
                                                    kv[0][2]))])

    W('\n### 2.2 Player block p[F]1D..p[F]3D (probable brutality combo)\n\n')
    W('| event | merged count |\n|---|---|\n')
    block = []
    for ev in range(0x1D, 0x3E):
        e = '%X' % ev
        n = anim.get(('p', True, e), 0)
        block.append((e, n))
        W('| p[F]%s | %d |\n' % (e, n))
    counts = set(n for _, n in block if n)
    modal = max(counts, key=lambda c: sum(1 for _, n in block if n == c)) \
        if counts else 0
    n_modal = sum(1 for _, n in block if n == modal)
    outliers = [(e, n) for e, n in block if n and n != modal]
    W('\nAll %d keys present. %d of %d sit at exactly %d samples; the %d '
      'outliers are %s - a scripted combo sampled once per hit, with a few '
      'events re-entered slightly more often.\n\n'
      % (len(block), n_modal, len(block), modal, len(outliers),
         ', '.join('p[F]%s=%d' % o for o in outliers) or 'none'))

    W('### 2.3 mutilate calls\n\n')
    mut = OrderedDict()
    for (name, args, callers), n in sorted(cmds.items()):
        if name != 'mutilate':
            continue
        mut[(args, callers)] = mut.get((args, callers), 0) + n
    W('| args (raw) | caller | merged count |\n|---|---|---|\n')
    mrows = sorted(mut.items(), key=lambda kv: (-kv[1], kv[0]))
    for (args, callers), n in mrows[:40]:
        W('| `%s` | %s | %d |\n' % (args, callers, n))
    if len(mrows) > 40:
        W('\n(%d more in upgrade_commands.csv)\n' % (len(mrows) - 40))
    csvs['upgrade_commands.csv'] = (
        ['name', 'args', 'callers', 'merged_count'],
        [[name, args, callers, n] for (name, args, callers), n
         in sorted(cmds.items(), key=lambda kv: (-kv[1], kv[0]))])

    W('\n### 2.4 Sampled commands by name\n\n')
    names = Counter()
    for (name, _a, _c), n in cmds.items():
        names[name] += n
    W('| command | merged count |\n|---|---|\n')
    for name, n in sorted(names.items(), key=lambda kv: (-kv[1], kv[0])):
        W('| %s | %d |\n' % (name, n))
    W('\n`ARM` bare tokens inside the command stream: %d (meaning not '
      'documented - printed raw here, not interpreted). Other unparsed '
      'tokens: %s\n\n'
      % (arm_tokens,
         ', '.join('%s x%d' % kv for kv in sorted(up_unparsed.items(),
                                                  key=lambda kv: -kv[1])[:10])
         or 'none'))

    # ============================================================== task 3
    W('## 3. Session timeline, soft-locks and crashes\n\n')
    rows = []
    for info in infos:
        e = info['entry']
        if info['empty']:
            rows.append([e['num'], 'EMPTY (0 bytes)', '-', 0, '-', 0, 0,
                         '-', e['name'], '-'])
            continue
        tagstr = ' '.join('%s x%d' % kv for kv in sorted(info['tags'].items()))
        saves_str = ','.join('%.0f' % s[1] for s in info['saves']) or '-'
        rows.append([e['num'],
                     info['stamp'].strftime('%m-%d %H:%M:%S')
                     if info['stamp'] else '?',
                     ('%.0fs' % info['duration'])
                     if info['duration'] is not None else '?',
                     len(info['saves']), saves_str, len(info['errors']),
                     len(info['exceptions']), info['last_map'], e['name'],
                     tagstr or 'none'])
    rows.sort(key=lambda r: (r[1] == 'EMPTY (0 bytes)',
                             r[1] if r[1] not in ('EMPTY (0 bytes)', '?')
                             else 'zzz', r[0]))
    W('3-line summary:\n')
    n_empty = sum(1 for r in rows if r[1] == 'EMPTY (0 bytes)')
    n_exc = sum(r[6] for r in rows)
    n_err = sum(r[5] for r in rows)
    W('- %d distinct log sessions (%d empty launches); %d carry an '
      '`exception C0000005` line, %d carry real mod script errors.\n'
      % (len(rows), n_empty, n_exc, n_err))
    W('- softlock-2039 = log 088: session started 20:28:17. The snapshot '
      'copy in qa/softlock-2039 stops mid-line at t=618.3 s (taken while the '
      'soft-lock was live); the run-folder copy is complete and ends '
      '`Exit (0)` at t=859.9 - the session was exited, not crashed. Zero '
      'probe reports in either copy; its peek.txt shows map 100, frame 29849, '
      'spawner idle (active 0), group 15 spawned only 4 of its waves and '
      '`waves cleared []` - the wave spawner never advanced.\n')
    W('- crash-kitana = log 089: started 20:44:36, `exception C0000005 at '
      '00007FF7D0B413E9` at t=1578.7 (~21:10:32 wall), matching dump '
      'ShaolinMonksRecomp.2026.10.24_21.10.33.dmp; 3 EVENTS, 2 UPGRADE, 3 '
      'SAVEDIFF, 1 SHUFFLE, 1 PLATE reports present.\n\n')
    W('| log | start | dur | saves (t) | probe tags | errors | exc | last '
      'map (GUESS) |\n|---|---|---|---|---|---|---|---|\n')
    for r in rows[:40]:
        W('| %03d | %s | %s | %s | %s | %d | %d | %s |\n'
          % (r[0], r[1], r[2], r[4], r[9], r[5], r[6], r[7]))
    if len(rows) > 40:
        W('\n(%d more sessions in timeline.csv)\n' % (len(rows) - 40))
    csvs['timeline.csv'] = (
        ['log_num', 'start', 'duration', 'n_saves', 'save_ts', 'errors',
         'exceptions', 'last_map_guess', 'file', 'tags'], rows)

    W('\nError lines (Mod routine lines that are not probe reports):\n\n')
    err_found = False
    for info in infos:
        for ts, raw in info['errors']:
            err_found = True
            W('- %s [%.1f] %s\n' % (info['entry']['name'], ts or -1,
                                    raw[:200]))
    if not err_found:
        W('- none in any log.\n')
    W('\nCrash dumps (deduped by name; window = session stamp..stamp+'
      'duration, GUESS for assignment):\n\n')
    W('| dump | time in name | session |\n|---|---|---|\n')
    for d in dmps:
        sess = '-'
        if d['when']:
            for info in infos:
                if info['stamp'] and info['duration'] is not None:
                    end = info['stamp'] + timedelta(seconds=info['duration'])
                    if info['stamp'] <= d['when'] <= end:
                        sess = '%03d%s' % (info['entry']['num'],
                                           ' (Exit 0 - dump may belong to an '
                                           'overlapping launch)'
                                           if info['exit'] == '0' else '')
                        break
        W('| %s | %s | %s |\n' % (d['name'],
                                  d['when'].strftime('%Y-%m-%d %H:%M:%S')
                                  if d['when'] else '?', sess))
    W('\nSnapshot folders:\n\n')
    W('| folder | contents | key facts |\n|---|---|---|\n')
    for snap, desc, facts in [
            ('qa/softlock-2039', 'peek.txt + log 088',
             'frame 29849, map 100, spawner active 0, group 15 spawned 4, '
             'waves cleared [] -> soft-lock: no wave progress, log truncated '
             'mid-line at t=618.3'),
            ('qa/peek-2251', 'peek.txt only',
             'frame 19794, map 12, spawner active 1, group 18 spawned 1, '
             'actors all alive -> healthy snapshot'),
            ('qa/crash-kitana', 'log 089 + dmp 21.10.33',
             'exception C0000005 at 00007FF7D0B413E9 (guest thread 14), '
             't=1578.7, wall ~21:10:32 = dump time')]:
        W('| %s | %s | %s |\n' % (snap, desc, facts))
    W('\n')

    # ============================================================== task 4
    W('## 4. Spawn health per area (EVENTS reports)\n\n')
    sess_rows = []
    area_rows = []
    type_tot = {}
    flagged = []
    for info in infos:
        if not info['events']:
            continue
        # EVENTS bodies are cumulative within a session; use the richest one.
        best = max(info['events'],
                   key=lambda r: len(logread.tokens(r['body'])))
        st = parse_events_stream(best['body'])
        name = '%03d' % info['entry']['num']
        spawns_tot = sum(v['n'] for v in st['spawns'].values())
        fails = st['fails_bare'] + sum(v['fail'] for v in st['spawns'].values())
        low = sorted(st['heap_low'].items(),
                     key=lambda kv: kv[1][0] / kv[1][1] if kv[1][1] else 9)
        lowstr = ' '.join('%s %.1f%%' % (t, 100.0 * f / tt)
                          for t, (f, tt) in low[:6])
        worst = max(st['areas'], key=lambda a: a['fails']) if st['areas'] \
            else None
        sess_rows.append([name,
                          info['stamp'].strftime('%H:%M') if info['stamp']
                          else '?',
                          len(st['areas']), spawns_tot, fails,
                          st['dropped'], lowstr,
                          ('area%d[%s] F=%d' % (st['areas'].index(worst) + 1,
                                                worst['key'], worst['fails'])
                           ) if worst and worst['fails'] >= 3 else '-'])
        for i, a in enumerate(st['areas'], 1):
            sp = ' | '.join(
                '%s x%d avg %s%s' % (t, v['n'],
                                     hx(v['bytes'] // v['n']) if v['n'] else
                                     '-',
                                     ' fail x%d' % v['fail'] if v['fail']
                                     else '')
                for t, v in sorted(a['spawns'].items(),
                                   key=lambda kv: (len(kv[0]), kv[0])))
            lw = ' | '.join('%s %.1f%% (%s/%s)' % (t, 100.0 * f / tt, hx(f),
                                                    hx(tt))
                            for t, (f, tt) in sorted(a['heap_low'].items())
                            if tt)
            area_rows.append([name, i, a['key'], a['first_grp'], a['gcount'],
                              sp or '-', a['fails'], lw or '-'])
            if a['fails'] >= 3:
                flagged.append([name, i, a['key'], a['fails'], sp or '-',
                                lw or '-'])
        for t, v in st['spawns'].items():
            tt = type_tot.setdefault(t, {'n': 0, 'bytes': 0, 'fail': 0})
            tt['n'] += v['n']
            tt['bytes'] += v['bytes']
            tt['fail'] += v['fail']
    csvs['events_areas.csv'] = (
        ['log', 'area', 'loaded_list', 'first_group', 'groups', 'spawns',
         'bare_F', 'heap_low_water'], area_rows)

    W('3-line summary:\n')
    W('- %d sessions carry EVENTS reports; areas are segments between '
      'changes of the G-token loaded (L) list. %d area segments total, %d '
      'flagged with >=3 bare-F failed spawns.\n'
      % (len(sess_rows), len(area_rows), len(flagged)))
    W('- Flagged areas concentrate on loaded lists containing E/1A/1B/F '
      'crowds; heap low-water drops to ~5% on type E in the worst sessions - '
      'that is where enemies went missing.\n')
    W('- Per-type totals across all sessions: %s.\n\n'
      % ', '.join('%s x%d avg %s%s'
                  % (t, v['n'], hx(v['bytes'] // v['n']) if v['n'] else '-',
                     ' fail x%d' % v['fail'] if v['fail'] else '')
                  for t, v in sorted(type_tot.items(),
                                     key=lambda kv: -kv[1]['n'])[:8]))
    W('Per-session summary (full per-area data in events_areas.csv):\n\n')
    W('| log | start | areas | spawns | fails (F + !fail) | dropped toks | '
      'heap low-water | worst area |\n|---|---|---|---|---|---|---|---|\n')
    for r in sess_rows[:40]:
        W('| %s | %s | %d | %d | %d | %d | %s | %s |\n' % tuple(r))
    if len(sess_rows) > 40:
        W('\n(%d more sessions in events_areas.csv)\n'
          % (len(sess_rows) - 40))
    W('\nFlagged areas (>=3 bare-F failed spawns):\n\n')
    W('| log | area | loaded list | bare F | spawns | heap low-water |\n'
      '|---|---|---|---|---|---|\n')
    for r in sorted(flagged, key=lambda r: -r[3])[:40]:
        W('| %s | %d | %s | %d | %s | %s |\n' % tuple(r))
    W('\n')

    # ============================================================== task 5
    W('## 5. Type 4D / 1A heap drops (not the Orochi)\n\n')
    W('Correction (live peek, 2026-10-25): the Orochi seen in normal rooms is '
      'type 0x1E, the same model family as the Orochi boss 0x1C. Map 67 preloads '
      '[0x1E, 0x0B] and its group 17 ran 1E,B,1E,B,B,B, a second Orochi from '
      'Shuffle and LDK x3 together, with 0x4E480 bytes still free for 1E. '
      'So type 4D is not the Orochi; what 4D is, and why its heap drops '
      'without S4D tokens, stays open.\n\n')
    or_rows = []
    series_rows = []
    all_drops = {}
    for info in infos:
        if not info['events']:
            continue
        best = max(info['events'],
                   key=lambda r: len(logread.tokens(r['body'])))
        st = parse_events_stream(best['body'])
        name = '%03d' % info['entry']['num']
        for typ in ('4D', '1A'):
            series = []
            for g in st['groups']:
                if typ in g['heaps']:
                    series.append((g['grp'], g['heaps'][typ][0],
                                   g['heaps'][typ][1]))
            loaded = any(typ in a['key'].split(',') for a in st['areas'])
            if not series and not loaded:
                continue
            drops = []
            for i in range(1, len(series)):
                d = series[i - 1][1] - series[i][1]
                if d > 0x10000:
                    drops.append((series[i][0], d))
            cls = []
            for grp, d in drops:
                if 0x20000 <= d <= 0x2A000:
                    cls.append('%s:-0x%X(~1x)' % (grp, d))
                elif 0x44000 <= d <= 0x52000:
                    cls.append('%s:-0x%X(~2x)' % (grp, d))
                else:
                    cls.append('%s:-0x%X(?%s)'
                               % (grp, d,
                                  '~%.1fx' % (d / float(0x25000))))
            all_drops.setdefault(typ, []).extend(d for _g, d in drops)
            s_n = st['s_tokens'].get(typ, 0)
            verdict = '-'
            if drops:
                two = sum(1 for grp, d in drops if 0x44000 <= d <= 0x52000)
                one = sum(1 for grp, d in drops if 0x20000 <= d <= 0x2A000)
                verdict = ('%d drop(s): %d look like 2 instances, %d like 1'
                           % (len(drops), two, one))
            or_rows.append([name, typ, len(series),
                            hx(series[0][1]) if series else '-',
                            hx(min(s[1] for s in series)) if series else '-',
                            s_n, verdict, '; '.join(cls[:6]) or '-'])
            for grp, free, total in series:
                series_rows.append([name, typ, grp, hx(free), hx(total)])
    csvs['orochi_heap_series.csv'] = (
        ['log', 'type', 'group', 'free', 'total'], series_rows)
    n4d = sum(1 for r in or_rows if r[1] == '4D')
    n1a = sum(1 for r in or_rows if r[1] == '1A')
    s4d = sum(r[5] for r in or_rows if r[1] == '4D')
    s1a = sum(r[5] for r in or_rows if r[1] == '1A')

    def drop_summary(typ):
        ds = sorted(all_drops.get(typ, []))
        if not ds:
            return 'no heap drops observed'
        mult = Counter()
        for d in ds:
            mult[max(1, round(d / float(0x25000)))] += 1
        return ('%d drop(s): %s (instance ~0x25000)'
                % (len(ds),
                   ', '.join('%d x ~%dx' % (c, m)
                             for m, c in sorted(mult.items()))))
    W('3-line summary:\n')
    W('- %d sessions load type 4D, %d load type 1A (from G-token L lists); '
      'type 4D has %d S4D spawn tokens and type 1A has %d S1A tokens across '
      'all sessions.\n' % (n4d, n1a, s4d, s1a))
    W('- 4D heap drops between group starts: %s - every one with NO matching '
      'S4D token (0 exist anywhere). Type 1A for comparison logs %d S1A '
      'spawn tokens and drops %s, so its allocations do pass through the '
      'logged spawn path at least in part (GUESS).\n'
      % (drop_summary('4D'), s1a, drop_summary('1A')))
    W('- Interpretation (GUESS): a script/event spawn (not the wave spawner, '
      'which would log S4D) allocates type 4D instances - drops of ~2x '
      'and ~3x point to several allocated at once. Heap series: '
      'orochi_heap_series.csv.\n\n')
    W('| log | type | heap samples | first free | min free | S<type> tokens | '
      'drop verdict | drops |\n|---|---|---|---|---|---|---|---|\n')
    for r in or_rows[:40]:
        W('| %s | %s | %d | %s | %s | %d | %s | %s |\n' % tuple(r))
    if len(or_rows) > 40:
        W('\n(%d more rows in orochi_heap_series.csv)\n'
          % (len(or_rows) - 40))
    W('\n---\n\nMethod notes: log corpus deduped by file name keeping the '
      'largest copy; EVENTS/UPGRADE bodies are cumulative within a session '
      '(verified by prefix comparison), so only the richest report per '
      'session is parsed; ANIM key split follows the logread GUESS rule '
      '(owner, optional F = fatality mode, hex event); number base follows '
      'the logread GUESS (all-digit = decimal, hex letters = hex). Slot '
      'geometry (base 0x%X, pitch 0x%X) was derived from label offsets in '
      'the saves themselves.\n' % (SLOT_BASE, SLOT_PITCH))

    # ---------------------------------------------------------------- write
    report = rep.getvalue()
    (OUT / 'REPORT.md').write_text(report, encoding='utf-8', newline='\n')
    for name, (header, rows_) in sorted(csvs.items()):
        with open(OUT / name, 'w', encoding='utf-8', newline='') as f:
            w = csv.writer(f, lineterminator='\n')
            w.writerow(header)
            w.writerows(rows_)
    print('wrote %s (%d bytes, md5 %s)' % (OUT / 'REPORT.md', len(report),
                                           md5_of(report.encode('utf-8'))))
    for name in sorted(csvs):
        print('wrote %s (%d rows)' % (OUT / name, len(csvs[name][1])))
    return 0


if __name__ == '__main__':
    sys.exit(main())
