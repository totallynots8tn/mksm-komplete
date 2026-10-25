#!/usr/bin/env python3
"""Human-readable summary of Shaolin Monks Recomp QA logs.

Reads %LOCALAPPDATA%/Shaolin Monks Recomp/logs/shaolin-recomp_NNN.log and
prints, per log: session facts, real mod script errors, parsed routine-mod
reports (EVENTS / PLATE / SHUFFLE / UPGRADE / PLATE0xx) and gamepad input
counts. Read-only: nothing outside the logs folder is written.

Tokens that do not match the documented grammar are printed raw under
"unparsed" instead of being guessed at.
"""

import argparse
import datetime
import os
import re
import sys
from collections import Counter, OrderedDict
from pathlib import Path

RECOMP_DIR = Path(os.environ.get('LOCALAPPDATA', '')) / 'Shaolin Monks Recomp'
LOGS_DIR = RECOMP_DIR / 'logs'
CRASH_DIR = RECOMP_DIR / 'crashes'

# Report tags this reader knows how to parse.
KNOWN_TAGS = frozenset((
    'EVENTS', 'PLATE', 'SHUFFLE', 'UPGRADE',
    'PLATE051', 'PLATE052', 'PLATE054', 'PLATE060',
))
# Older probe builds emitted their own report tags. They are reports, not
# script errors, so they are dumped raw in section C rather than flagged in B.
LEGACY_TAGS = frozenset(('TRACE', 'PROBE25', 'PROBE90'))

DISABLED = '. Script disabled for this session.'

RE_LINE = re.compile(r'^\[\s*(\d+\.\d+)\]\s+\[(\w+)\]\s+\[([0-9a-zA-Z]+)\]\s+(.*)$')
RE_STAMP = re.compile(r'Shaolin Monks Recomp \(default\.xbe\), '
                      r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})')
RE_MODS = re.compile(r'Mods: (\d+) routine scripts active')
RE_SAVEMETA = re.compile(r'^open (U:\\.+?)\\+SaveMeta\.xbx$')
RE_SAVEDAT = re.compile(r'^open (U:\\.+?)\\+save\.dat$')
RE_EXIT = re.compile(r'Exit \((-?\d+)\)')
RE_ROUTINE = re.compile(r'^Mod routine: ([^:]+):\s*(.*)$')
RE_INPUT = re.compile(r'^input: gamepad port=(\d+) buttons=([0-9A-Fa-f]{4}) '
                      r'A=(-?\d+) B=(-?\d+)')

# ---- EVENTS body tokens -------------------------------------------------
RE_GROUP = re.compile(r'^G([0-9A-Fa-f]+)n(\d+)p(\d+)\[(.*?)\]L(.*)$')
RE_SPAWN = re.compile(r'^S([0-9A-Fa-f]+):(!fail|[0-9A-Fa-f]+)$')
RE_FAIL = re.compile(r'^F$')
RE_DEATH = re.compile(r'^D([0-9A-Fa-f]+)@(.*)$')
RE_KILL = re.compile(r'^K([0-9A-Fa-f]+):([^@]*)@(.*)$')
RE_DMG = re.compile(r'^A([0-9A-Fa-f]+):([0-9A-Fa-f]+)>([0-9A-Fa-f]+)$')
RE_BODY = re.compile(r'^B([0-9A-Fa-f]+):([0-9A-Fa-f]+)>([0-9A-Fa-f]+)$')
RE_XPSET = re.compile(r'^X(\d+):\+([0-9A-Fa-f]+)c(-?\d+)@(.*)$')
RE_XP = re.compile(r'^XP\+([0-9A-Fa-f]+)c(-?\d+)<(.*)$')
RE_DROP = re.compile(r'^\.*\((\d+)\s+dropped\)\.*$')

# ---- SHUFFLE ------------------------------------------------------------
RE_AREA = re.compile(r'^\{mode=(-?\d+)\s+frame=(\d+)\s+slots=(\d+)\s+'
                     r'eligible=(\d+)\s+freegates=(\d+)\s+'
                     r'loaded=\[(.*?)\]\s*\|\s*(.*?)\}$')
RE_SHUF_TYPE = re.compile(r'^([0-9A-Fa-f]+)=(\d+)([A-Za-z]*)$')

# ---- UPGRADE ------------------------------------------------------------
RE_CMD = re.compile(r'^([A-Za-z_][\w]*)\[(.*?)\]@(\S+)$')
RE_ANIM = re.compile(r'^([po])([0-9A-Fa-f]*)=(\d+)$')
RE_STATE = re.compile(r'^f([0-9A-Fa-f]+):(-?[\dA-Fa-f]+)/(-?[\dA-Fa-f]+)/'
                      r'(-?[\dA-Fa-f]+)/(-?[\dA-Fa-f]+)$')


def num(text):
    """Parse a report number. All-digit fields are decimal; anything with a
    hex letter is hex (GUESS: the probe prints HP/XP in decimal and
    addresses/sizes in hex)."""
    try:
        return int(text, 10)
    except ValueError:
        return int(text, 16)


def hx(value):
    return '0x%X' % value


# --------------------------------------------------------------------------
# log discovery
# --------------------------------------------------------------------------

def log_files():
    if not LOGS_DIR.is_dir():
        return []
    out = []
    for path in LOGS_DIR.glob('shaolin-recomp_*.log'):
        m = re.search(r'shaolin-recomp_(\d+)\.log$', path.name)
        if m:
            out.append((int(m.group(1)), path))
    out.sort(key=lambda pair: pair[0])
    return out


def select(args):
    files = log_files()
    if not files:
        sys.exit('no logs found in %s' % LOGS_DIR)
    if args.log is not None:
        try:
            want = int(args.log, 10)
        except ValueError:
            sys.exit('--log needs a number, got %r' % args.log)
        picked = [p for n, p in files if n == want]
        if not picked:
            sys.exit('no log numbered %d (have %d..%d)'
                     % (want, files[0][0], files[-1][0]))
        return picked
    if args.last is not None:
        if args.last < 1:
            sys.exit('--last needs N >= 1')
        return [p for _, p in files[-args.last:]]
    return [files[-1][1]]


# --------------------------------------------------------------------------
# parsing
# --------------------------------------------------------------------------

def read_log(path):
    lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    recs = []
    for raw in lines:
        m = RE_LINE.match(raw)
        if m:
            recs.append((float(m.group(1)), m.group(2), m.group(3),
                         m.group(4), raw))
        elif raw.strip():
            recs.append((None, None, None, raw, raw))
    return lines, recs


def session_facts(recs):
    facts = OrderedDict()
    stamp = None
    duration = None
    mods = None
    saves = []
    exit_code = None
    prev_meta = None
    for ts, _lvl, _thr, msg, _raw in recs:
        if stamp is None:
            m = RE_STAMP.search(msg)
            if m:
                stamp = datetime.datetime.strptime(m.group(1),
                                                   '%Y-%m-%d %H:%M:%S')
        m = RE_MODS.search(msg)
        if m:
            mods = int(m.group(1))
        meta = RE_SAVEMETA.match(msg)
        if meta:
            prev_meta = (ts, meta.group(1))
            continue
        dat = RE_SAVEDAT.match(msg)
        if dat and prev_meta is not None and prev_meta[1] == dat.group(1):
            saves.append((prev_meta[0], ts, dat.group(1)))
            prev_meta = None
            continue
        prev_meta = None
        m = RE_EXIT.search(msg)
        if m:
            exit_code = m.group(1)
        if ts is not None:
            duration = ts
    facts['stamp'] = stamp
    facts['duration'] = duration
    facts['mods'] = mods
    facts['saves'] = saves
    facts['exit'] = exit_code
    return facts


def crashes_in_session(path, facts):
    """Crash dumps whose mtime falls inside the session window.

    An empty log has no timestamps at all, so it falls back to the log file's
    own mtime and a small window around it (GUESS: those launches died before
    writing a header).
    """
    if not CRASH_DIR.is_dir():
        return [], 'no crashes folder', False
    stamps = [p.stat().st_mtime for p in [path]]
    if facts['stamp'] is None:
        anchor = datetime.datetime.fromtimestamp(stamps[0])
        start = anchor - datetime.timedelta(minutes=5)
        end = anchor + datetime.timedelta(minutes=1)
        guessed = True
    else:
        start = facts['stamp']
        end = start + datetime.timedelta(seconds=facts['duration'] or 0.0)
        guessed = False
    hits = []
    for dump in sorted(CRASH_DIR.glob('*.dmp')):
        mtime = datetime.datetime.fromtimestamp(dump.stat().st_mtime)
        if start <= mtime <= end:
            hits.append((dump.name, mtime))
    return hits, None, guessed


def split_reports(recs):
    """Return (errors, reports): routine lines with an unknown tag vs known."""
    errors, reports = [], []
    for ts, lvl, _thr, msg, raw in recs:
        m = RE_ROUTINE.match(msg)
        if not m:
            continue
        mod, rest = m.group(1), m.group(2)
        tag = rest.split(' ', 1)[0] if rest else ''
        args = rest[len(tag):].strip()
        if args.endswith(DISABLED):
            args = args[:-len(DISABLED)].rstrip()
        entry = {'ts': ts, 'level': lvl, 'mod': mod, 'tag': tag,
                 'args': args, 'rest': rest, 'raw': raw}
        if tag in KNOWN_TAGS:
            reports.append(entry)
        elif tag in LEGACY_TAGS:
            entry['legacy'] = True
            reports.append(entry)
        else:
            errors.append(entry)
    return errors, reports


def split_head_body(rest, tag):
    """'<reason> <fields> | <body>' -> (reason, fields, body).

    SHUFFLE has no '|'-separated header: its body is a run of {...} blocks
    whose insides also contain ' | ', so the body starts at the first '{'.
    """
    if tag == 'SHUFFLE':
        idx = rest.find('{')
        head, body = (rest, '') if idx < 0 else (rest[:idx], rest[idx:])
    else:
        head, sep, body = rest.partition(' | ')
        if not sep:
            body = ''
    words = head.split()
    reason = ''
    if words and '=' not in words[0]:
        reason = words[0]
        words = words[1:]
    return reason, words, body


def tokens(text):
    """Whitespace-split, but keep bracketed groups and the '...(N dropped)...'
    marker together: both contain spaces."""
    out, buf, depth, dropping = [], [], 0, False
    for word in text.replace(' | ', ' ').split():
        buf.append(word)
        depth += word.count('[') - word.count(']')
        if word.startswith('...(') and not word.endswith(')...'):
            dropping = True
        if word.endswith(')...'):
            dropping = False
        if depth <= 0 and not dropping:
            out.append(' '.join(buf))
            buf, depth = [], 0
    if buf:
        out.append(' '.join(buf))
    return [t for t in out if t and t != '|']


def parse_events(body):
    st = {
        'deaths': Counter(), 'kills': Counter(), 'dmg': Counter(),
        'bodydmg': Counter(), 'xp_total': 0, 'xp_events': 0, 'xp_big': 0,
        'xp_big_raw': '', 'xpset': [], 'groups': [], 'spawns': {},
        'fails_bare': 0, 'dropped': 0, 'unparsed': [],
    }
    for tok in tokens(body):
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
                heaps[name] = (int(free, 16), int(total, 16))
            st['groups'].append({'grp': m.group(1), 'count': int(m.group(2)),
                                 'pool': m.group(3), 'heaps': heaps,
                                 'loaded': m.group(5)})
            continue
        m = RE_SPAWN.match(tok)
        if m:
            typ = m.group(1).upper()
            slot = st['spawns'].setdefault(
                typ, {'n': 0, 'bytes': 0, 'fail': 0})
            if m.group(2) == '!fail':
                slot['fail'] += 1
            else:
                slot['n'] += 1
                slot['bytes'] += int(m.group(2), 16)
            continue
        if RE_FAIL.match(tok):
            st['fails_bare'] += 1
            continue
        m = RE_XP.match(tok)
        if m:
            amt = num(m.group(1))
            st['xp_total'] += amt
            st['xp_events'] += 1
            if amt > st['xp_big']:
                st['xp_big'], st['xp_big_raw'] = amt, m.group(1)
            continue
        m = RE_XPSET.match(tok)
        if m:
            st['xpset'].append((m.group(1), m.group(2), m.group(3),
                                m.group(4)))
            continue
        m = RE_KILL.match(tok)
        if m:
            st['kills'][m.group(1).upper()] += 1
            continue
        m = RE_DEATH.match(tok)
        if m:
            st['deaths'][m.group(1).upper()] += 1
            continue
        m = RE_DMG.match(tok)
        if m:
            st['dmg'][m.group(1).upper()] += 1
            continue
        m = RE_BODY.match(tok)
        if m:
            st['bodydmg'][m.group(1).upper()] += 1
            continue
        m = RE_DROP.match(tok)
        if m:
            st['dropped'] += int(m.group(1))
            continue
        st['unparsed'].append(tok)
    return st


def render_events(st, out):
    def slots(counter):
        return ' '.join('%s:%d' % (k, v)
                        for k, v in sorted(counter.items(),
                                           key=lambda kv: (len(kv[0]), kv[0])))
    if st['deaths'] or st['kills']:
        out.append('    deaths/slot: %s' % (slots(st['deaths']) or '-'))
        out.append('    instant kills/slot: %s' % (slots(st['kills']) or '-'))
    if st['dmg'] or st['bodydmg']:
        out.append('    damage applied (A)/slot: %s | body damage (B)/slot: %s'
                   % (slots(st['dmg']) or '-', slots(st['bodydmg']) or '-'))
    if st['xp_events'] or st['xpset']:
        out.append('    XP awarded: %s over %d award(s), biggest %s%s'
                   % (format(st['xp_total'], ','), st['xp_events'],
                      format(st['xp_big'], ','),
                      ' (raw %s)' % st['xp_big_raw']
                      if st['xp_big_raw'] != str(st['xp_big']) else ''))
    if st['xpset']:
        out.append('    XP set calls: %s'
                   % ', '.join('p%s=+%s c%s @%s' % s for s in st['xpset'][:8]))
    if st['groups']:
        ids = Counter('%s(n%s)' % (g['grp'], g['count']) for g in st['groups'])
        pools = Counter(g['pool'] for g in st['groups'])
        out.append('    group starts: %d | ids %s | pool free %s'
                   % (len(st['groups']),
                      ', '.join('%s x%d' % (k, v)
                                for k, v in sorted(ids.items(),
                                                   key=lambda kv: -kv[1])),
                      ', '.join('%s x%d' % kv for kv in sorted(pools.items()))))
        low = {}
        for g in st['groups']:
            for typ, (free, total) in g['heaps'].items():
                if not total:
                    continue
                pct = 100.0 * free / total
                if typ not in low or pct < low[typ][0]:
                    low[typ] = (pct, free, total)
        if low:
            out.append('    heap low water (%% of total): %s'
                       % ' | '.join('%s %.1f%% (%s/%s)'
                                    % (t, v[0], hx(v[1]), hx(v[2]))
                                    for t, v in sorted(low.items(),
                                                       key=lambda kv: kv[1][0])))
    if st['spawns']:
        parts = []
        for typ in sorted(st['spawns'], key=lambda t: (len(t), t)):
            s = st['spawns'][typ]
            avg = hx(s['bytes'] // s['n']) if s['n'] else '-'
            parts.append('%s x%d avg %s%s'
                         % (typ, s['n'], avg,
                            ' fail x%d' % s['fail'] if s['fail'] else ''))
        out.append('    spawns: %s' % ' | '.join(parts))
    if st['fails_bare']:
        out.append('    spawn failures (bare F): %d' % st['fails_bare'])
    if st['dropped']:
        out.append('    omitted middle: %d token(s) dropped' % st['dropped'])


def parse_shuffle(body):
    """'areas=N {..} {..}' -> (declared, [area dicts], unparsed)."""
    m = re.match(r'^\s*areas=(\d+)\s*(.*)$', body, re.S)
    declared = int(m.group(1)) if m else None
    rest = m.group(2) if m else body
    areas, unparsed = [], []
    for chunk in re.findall(r'\{.*?\}', rest, re.S):
        a = RE_AREA.match(chunk.strip())
        if not a:
            unparsed.append(chunk)
            continue
        types = []
        for tok in a.group(7).split():
            t = RE_SHUF_TYPE.match(tok)
            if not t:
                unparsed.append(tok)
                continue
            types.append({'type': t.group(1).upper(), 'count': int(t.group(2)),
                          'flags': t.group(3)})
        areas.append({'mode': a.group(1), 'frame': int(a.group(2)),
                      'slots': int(a.group(3)), 'eligible': int(a.group(4)),
                      'freegates': int(a.group(5)),
                      'loaded': a.group(6), 'types': types})
    leftover = re.sub(r'\{.*?\}', ' ', rest, flags=re.S)
    unparsed.extend(t for t in leftover.split() if t)
    return declared, areas, unparsed


def render_shuffle(declared, areas, unparsed, out):
    if declared is not None and declared != len(areas):
        out.append('    areas declared %d, parsed %d' % (declared, len(areas)))
    for i, a in enumerate(areas, 1):
        out.append('    area%d mode=%s frame=%d slots=%d eligible=%d '
                   'freegates=%d loaded=[%s]'
                   % (i, a['mode'], a['frame'], a['slots'], a['eligible'],
                      a['freegates'], a['loaded']))
        groups = OrderedDict()
        for t in a['types']:
            groups.setdefault(t['flags'] or '(none)', []).append(
                '%s=%d' % (t['type'], t['count']))
        for flags, members in groups.items():
            out.append('      flags %s: %s' % (flags, ' '.join(members)))


def parse_upgrade(body):
    """Body = sampled commands, then optional '| ANIM ...' and '| STATE ...'."""
    sections = [s.strip() for s in body.split(' | ')]
    cmds, anim, state, unparsed = [], {}, [], []
    for sec in sections:
        if sec.startswith('ANIM '):
            for tok in tokens(sec[len('ANIM '):]):
                m = RE_ANIM.match(tok)
                if not m:
                    unparsed.append(tok)
                    continue
                owner, rest, count = m.group(1), m.group(2), int(m.group(3))
                # GUESS: an F directly after the owner with hex digits still
                # to follow is the fatality-mode marker; otherwise the whole
                # remainder is the hex event type (so p1F4 = owner p, event 1F4).
                fatal = rest.startswith('F') and len(rest) > 1
                event = rest[1:] if fatal else rest
                anim[(owner, fatal, event.upper())] = count
            continue
        if sec.startswith('STATE '):
            for tok in tokens(sec[len('STATE '):]):
                m = RE_STATE.match(tok)
                if not m:
                    unparsed.append(tok)
                    continue
                state.append((m.group(1).upper(), m.groups()[1:]))
            continue
        for tok in tokens(sec):
            m = RE_CMD.match(tok)
            if m:
                cmds.append((m.group(1), m.group(2), m.group(3)))
            else:
                unparsed.append(tok)
    return cmds, anim, state, unparsed


def render_upgrade(cmds, anim, state, unparsed, out):
    if cmds:
        names = Counter(c[0] for c in cmds)
        out.append('    sampled commands: %s'
                   % ', '.join('%s x%d' % kv
                               for kv in sorted(names.items(),
                                                key=lambda kv: -kv[1])))
        seen = Counter(cmds)
        for (name, args, callers), n in sorted(seen.items(),
                                               key=lambda kv: (kv[0][0], -kv[1])):
            out.append('      %s[%s]@%s x%d' % (name, args, callers, n))
    if anim:
        out.append('    ANIM histogram (%d keys, %s samples), sorted by count:'
                   % (len(anim), format(sum(anim.values()), ',')))
        entries = sorted(anim.items(), key=lambda kv: (-kv[1], kv[0]))
        rendered = ['%s%s=%d' % (k[0], ('[F]%s' % k[2]) if k[1]
                                 else '.%s' % (k[2] or '-'), v)
                    for k, v in entries]
        line = '      '
        for item in rendered:
            if len(line) + len(item) + 1 > 118 and line.strip():
                out.append(line.rstrip())
                line = '      '
            line += item + ' '
        if line.strip():
            out.append(line.rstrip())
        out.append('      key = <owner p|o> then ".<hex event>" or '
                   '"[F]<hex event>" = fatality mode (GUESS split rule)')
    if state:
        out.append('    STATE transitions: %s'
                   % '  '.join('f%s=%s/%s/%s/%s' % ((k,) + tuple(v))
                               for k, v in state))


def render_report(rep, out):
    ts = '%.3f' % rep['ts'] if rep['ts'] is not None else '?'
    head = '  [%s] %s: %s' % (ts, rep['mod'], rep['tag'])
    if rep.get('legacy'):
        out.append(head + '  (older probe tag, printed raw)')
        out.append('    ' + rep['rest'])
        return
    reason, fields, body = split_head_body(rep['args'], rep['tag'])
    out.append('%s  reason=%s  %s'
               % (head, reason or '-', ' '.join(fields) if fields else ''))
    if rep['tag'] == 'EVENTS':
        render_events(parse_events(body), out)
    elif rep['tag'] == 'SHUFFLE':
        declared, areas, unparsed = parse_shuffle(body)
        render_shuffle(declared, areas, unparsed, out)
        if unparsed:
            out.append('    unparsed: %s' % ' '.join(unparsed[:20]))
    elif rep['tag'] == 'UPGRADE':
        cmds, anim, state, unparsed = parse_upgrade(body)
        render_upgrade(cmds, anim, state, unparsed, out)
        if unparsed:
            out.append('    unparsed: %s' % ' '.join(unparsed[:20]))
    else:  # PLATE and PLATE0xx
        toks = tokens(body)
        for tok in toks[:40]:
            out.append('    %s' % tok)
        if len(toks) > 40:
            out.append('    ... %d more body token(s)' % (len(toks) - 40))


def parse_input(recs):
    total = 0
    buttons = Counter()
    ports = Counter()
    for _ts, _lvl, _thr, msg, _raw in recs:
        m = RE_INPUT.match(msg)
        if not m:
            continue
        total += 1
        ports[m.group(1)] += 1
        if int(m.group(2), 16) != 0:
            buttons[m.group(2).upper()] += 1
    return total, buttons, ports


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def summarise(path):
    out = []
    lines, recs = read_log(path)
    facts = session_facts(recs)

    out.append('=== %s ===' % path.name)
    out.append('A. Session')
    dur = facts['duration']
    if not lines:
        out.append('  EMPTY LOG (%d bytes), file mtime %s - this launch wrote '
                   'nothing, so it has no timestamps'
                   % (path.stat().st_size,
                      datetime.datetime.fromtimestamp(path.stat().st_mtime)))
    else:
        out.append('  start: %s | duration: %s | last line: %s'
                   % (facts['stamp'] or 'unknown',
                      ('%.1fs' % dur) if dur is not None else 'unknown',
                      lines[-1].strip()[:100]))
    out.append('  Mods: %s'
               % ('%d routine scripts active' % facts['mods']
                  if facts['mods'] is not None
                  else 'no "Mods: N routine scripts active" line'))
    if facts['saves']:
        out.append('  saves: %d' % len(facts['saves']))
        for meta_ts, dat_ts, container in facts['saves']:
            out.append('    %s -> %s  %s\\save.dat'
                       % ('%.3f' % meta_ts if meta_ts is not None else '?',
                          '%.3f' % dat_ts if dat_ts is not None else '?',
                          container))
    else:
        out.append('  saves: none (no SaveMeta.xbx -> save.dat pair)')
    if facts['exit'] is not None:
        out.append('  ends with: Exit (%s)%s'
                   % (facts['exit'],
                      '' if facts['exit'] == '0' else '  <-- non-zero'))
    else:
        out.append('  ends with: no "Exit (0)" line (killed, crashed or '
                   'still running)')
    crashes, note, guessed = crashes_in_session(path, facts)
    if crashes:
        out.append('  crash dumps in this session%s:'
                   % (' (GUESS: matched by log file mtime)' if guessed else ''))
        for name, mtime in crashes:
            out.append('    %s  (mtime %s)' % (name, mtime))
        if facts['exit'] == '0':
            out.append('    note: this log ends with Exit (0), so the dump may '
                       'belong to a second, overlapping launch')
    else:
        out.append('  crash dumps in this session: none%s'
                   % (' (%s)' % note if note else ''))

    errors, reports = split_reports(recs)
    out.append('B. Mod errors (%d)' % len(errors))
    if errors:
        for e in errors:
            out.append('  [%s] %s' % ('%.3f' % e['ts']
                                      if e['ts'] is not None else '?', e['raw']))
    else:
        out.append('  none')

    out.append('C. Reports (%d)' % len(reports))
    if not reports:
        out.append('  none')
    for rep in reports:
        render_report(rep, out)

    total, buttons, ports = parse_input(recs)
    out.append('D. Input')
    if total:
        out.append('  gamepad lines: %d (port%s %s)'
                   % (total, 's' if len(ports) > 1 else '',
                      ', '.join('%s x%d' % kv for kv in sorted(ports.items()))))
        if buttons:
            out.append('  distinct non-zero buttons: %s'
                       % ', '.join('%s x%d' % kv
                                   for kv in sorted(buttons.items(),
                                                    key=lambda kv: -kv[1])))
        else:
            out.append('  distinct non-zero buttons: none')
    else:
        out.append('  no "input: gamepad" lines')
    out.append('')
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(
        description='Summarise Shaolin Monks Recomp QA logs.',
        epilog='examples: logread.py newest | logread.py --last 2 | '
               'logread.py --log 071')
    ap.add_argument('target', nargs='?', default='newest',
                    help='"newest" (default): the newest log')
    ap.add_argument('--last', type=int, metavar='N',
                    help='the N newest logs')
    ap.add_argument('--log', metavar='NNN', help='one specific log number')
    args = ap.parse_args(argv)

    if args.target != 'newest' and args.last is None and args.log is None:
        sys.exit('unknown target %r (use "newest", --last N or --log NNN)'
                 % args.target)

    for path in select(args):
        for line in summarise(path):
            print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main())
