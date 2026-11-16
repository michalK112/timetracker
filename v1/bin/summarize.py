#!/usr/bin/env python3
"""TimeTracker: agreguje dzienny eksport ActivityWatch według reguł projektów.

Użycie: summarize.py EXPORT.json CONFIG.json > summary.json
CONFIG = {"projects":[...], "settings":{...}, "session":{...}|null}
Wynik: czas na projekt, pozycje (aplikacja + tytuł), oś czasu i nieprzypisane pozycje do oceny.
"""
import json, re, sys
from datetime import datetime, timedelta, timezone

BROWSERS = ['google chrome', 'chrome', 'safari', 'arc', 'microsoft edge', 'firefox', 'brave browser',
            'opera', 'vivaldi', 'zen', 'orion', 'chromium', 'dia']
TOOL_APPS = {
    'slack': ['slack'], 'figma': ['figma'], 'browser': BROWSERS,
    'mail': ['mail', 'microsoft outlook', 'outlook', 'spark', 'airmail', 'mimestream'],
    'meet': ['zoom.us', 'zoom', 'microsoft teams', 'teams', 'facetime', 'webex'],
    'code': ['code', 'visual studio code', 'cursor', 'zed', 'webstorm', 'xcode', 'sublime text', 'nova', 'windsurf'],
    'framer': ['framer'], 'notion': ['notion'],
    'terminal': ['terminal', 'iterm2', 'warp', 'ghostty', 'alacritty', 'kitty'],
    'invoices': [],
}
TOOL_WEB = {  # te narzędzia działają też w przeglądarce
    'invoices': ['fakturownia', 'infakt', 'wfirma', 'ifirma', 'saldeo', 'faktura'],
    'mail': ['mail.google.com', 'outlook.live.com', 'outlook.office'],
    'meet': ['meet.google.com', 'zoom.us/', 'teams.microsoft.com'],
    'figma': ['figma.com'], 'slack': ['app.slack.com'], 'notion': ['notion.so', 'notion.site'],
    'framer': ['framer.com'],
}


def ts(s):
    return datetime.fromisoformat(s.replace('Z', '+00:00'))


def intervals(events):
    out = []
    for e in events or []:
        try:
            a = ts(e['timestamp'])
        except Exception:
            continue
        out.append((a, a + timedelta(seconds=float(e.get('duration') or 0)), e.get('data') or {}))
    out.sort(key=lambda x: x[0])
    return out


def merge(spans, gap=0.0):
    spans = sorted(spans)
    out = []
    for a, b in spans:
        if out and (a - out[-1][1]).total_seconds() <= gap:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def active_spans(afk, idle_min):
    """Czas aktywny = okresy not-afk + krótkie przerwy afk (krótsze niż próg bezczynności)."""
    if not afk:
        return None  # brak danych o bezczynności: liczymy cały czas okien
    act = [(a, b) for a, b, d in afk if d.get('status') == 'not-afk']
    return merge(act, gap=idle_min * 60)


def clip(a, b, spans):
    if spans is None:
        return [(a, b)] if b > a else []
    out = []
    for s, e in spans:
        if e <= a:
            continue
        if s >= b:
            break
        x, y = max(a, s), min(b, e)
        if y > x:
            out.append((x, y))
    return out


CLEAN = [r'^\(\d+\)\s*', r'^[•●]\s*', r'\s+[-–—]\s+(Google Chrome|Safari|Arc|Microsoft Edge|Mozilla Firefox|Brave)$',
         r'\s*[-–—]\s*Audio playing$', r'\s+\(\d+\)$']


def clean_title(t):
    t = (t or '').strip()
    for p in CLEAN:
        t = re.sub(p, '', t)
    return t[:140]


def lc(s):
    return (s or '').lower()


def app_is(app, names):
    a = lc(app)
    return any(a == n or a.startswith(n + ' ') for n in names)


def match(project, app, text, url):
    """Zwraca (wynik, powód) lub (0, None). Wyższy wynik = pewniejsze dopasowanie."""
    best = (0, None)
    for t in project.get('tools') or []:
        typ = t.get('type')
        kws = [lc(k) for k in t.get('keywords') or [] if k.strip()]
        if typ == 'custom':
            in_tool = bool(t.get('app')) and lc(t['app']) in lc(app)
        else:
            in_tool = app_is(app, TOOL_APPS.get(typ, [])) or (
                app_is(app, BROWSERS) and any(d in lc(url) or d in text for d in TOOL_WEB.get(typ, [])))
        if not in_tool:
            continue
        if not kws:
            if typ != 'browser' and best[0] < 2:  # cała przeglądarka bez słów = zbyt szeroko
                best = (2, f"{typ}")
        else:
            hit = next((k for k in kws if k in text), None)
            if hit and best[0] < 4:
                best = (4, f"{typ}:{hit}")
    for k in project.get('keywords') or []:
        k = lc(k).strip()
        if k and k in text and best[0] < 3:
            best = (3, f"kw:{k}")
    return best


def main():
    exp = json.load(open(sys.argv[1]))
    cfg = json.load(open(sys.argv[2]))
    st = {'idleMinutes': 5, 'minBlockMinutes': 2, **(cfg.get('settings') or {})}
    projects = [p for p in cfg.get('projects') or [] if p.get('enabled', True)]
    session = set(((cfg.get('session') or {}).get('projectIds')) or [])
    order = {p['id']: (0 if p['id'] in session else 1, p.get('order', 99)) for p in projects}

    win = intervals(exp.get('window'))
    afk = intervals(exp.get('afk'))
    web = intervals(exp.get('web'))
    spans = active_spans(afk, st['idleMinutes'])

    pieces = []  # (start, end, app, title, url, project_id, reason)
    wi = 0
    for a, b, d in win:
        app = d.get('app') or '?'
        title = d.get('title') or ''
        for x, y in clip(a, b, spans):
            url = d.get('url') or ''  # TimeTracker.app zapisuje adres razem z oknem
            if not url and app_is(app, BROWSERS) and web:
                mid = x + (y - x) / 2
                while wi < len(web) and web[wi][1] < x - timedelta(minutes=10):
                    wi += 1
                for s, e, wd in web[max(0, wi - 5): wi + 50]:
                    if s <= mid <= e + timedelta(seconds=5):
                        url = wd.get('url') or ''
                        title = wd.get('title') or title
                        break
            text = lc(' '.join([app, title, url]))
            scored = [(match(p, app, text, url), p['id']) for p in projects]
            scored = [(s, pid) for s, pid in scored if s[0] > 0]
            if scored:
                scored.sort(key=lambda z: (-z[0][0], order[z[1]]))
                (_, why), pid = scored[0]
            else:
                pid, why = None, None
            pieces.append((x, y, app, clean_title(title), url, pid, why))

    # dedup: zdarzenia okien nie powinny się nakładać, ale na wszelki wypadek przycinamy nakładki
    pieces.sort(key=lambda p: p[0])
    fixed, last_end = [], None
    for p in pieces:
        x, y = p[0], p[1]
        if last_end and x < last_end:
            x = last_end
        if y > x:
            fixed.append((x, y) + p[2:])
            last_end = y
    pieces = fixed

    z = exp.get('tz') or '+0000'
    sign = -1 if z.startswith('-') else 1
    tz = timezone(sign * timedelta(hours=int(z[1:3]), minutes=int(z[3:5])))
    hm = lambda d: d.astimezone(tz).strftime('%H:%M')
    mins = lambda s: round(s / 60, 1)
    names = {p['id']: p.get('name') for p in projects}

    proj = {}
    for x, y, app, title, url, pid, why in pieces:
        key = pid or '_other'
        sec = (y - x).total_seconds()
        P = proj.setdefault(key, {'seconds': 0, 'items': {}})
        P['seconds'] += sec
        domain = re.sub(r'^https?://(www\.)?', '', url).split('/')[0] if url else ''
        ik = (app, title, domain)
        it = P['items'].setdefault(ik, {'seconds': 0, 'first': x, 'last': y, 'why': why})
        it['seconds'] += sec
        it['last'] = max(it['last'], y)

    min_block = st['minBlockMinutes'] * 60
    out_projects = []
    for key, P in sorted(proj.items(), key=lambda kv: -kv[1]['seconds']):
        items = sorted(P['items'].items(), key=lambda kv: -kv[1]['seconds'])
        shown = [{'app': a, 'title': t, 'domain': dmn, 'minutes': mins(v['seconds']),
                  'first': hm(v['first']), 'last': hm(v['last']), 'match': v['why']}
                 for (a, t, dmn), v in items if v['seconds'] >= min_block][:40]
        small = sum(v['seconds'] for _, v in items if v['seconds'] < min_block)
        out_projects.append({'id': key, 'name': names.get(key, 'Inne'), 'minutes': mins(P['seconds']),
                             'items': shown, 'smallItemsMinutes': mins(small)})

    # oś czasu: kolejne fragmenty tego samego projektu, przerwy < 5 min sklejone
    blocks = []
    for x, y, app, title, url, pid, why in pieces:
        k = pid or '_other'
        if blocks and blocks[-1]['p'] == k and (x - blocks[-1]['e']).total_seconds() < 300:
            blocks[-1]['e'] = y
            blocks[-1]['s_sec'] += (y - x).total_seconds()
        else:
            blocks.append({'p': k, 's': x, 'e': y, 's_sec': (y - x).total_seconds()})
    timeline = [{'project': names.get(b['p'], 'Inne'), 'from': hm(b['s']), 'to': hm(b['e']), 'minutes': mins(b['s_sec'])}
                for b in blocks if b['s_sec'] >= 180]

    # wpisy do kalendarza: ciągłe bloki pracy nad jednym projektem.
    # Wtrącenia krótsze niż 3 min nie przerywają bloku; bloki tego samego projektu
    # rozdzielone tylko takimi wtrąceniami (do 10 min przerwy) są łączone.
    raw = []
    for pc in pieces:
        k = pc[5] or '_other'
        if raw and raw[-1]['p'] == k and (pc[0] - raw[-1]['e']).total_seconds() < 300:
            raw[-1]['e'] = pc[1]
            raw[-1]['pcs'].append(pc)
        else:
            raw.append({'p': k, 's': pc[0], 'e': pc[1], 'pcs': [pc]})
    secs = lambda b: sum((x[1] - x[0]).total_seconds() for x in b['pcs'])
    merged = []
    for b in raw:
        if secs(b) < 180:
            continue  # wtrącenie: liczy się do sum projektu, ale nie tworzy wpisu
        last = merged[-1] if merged else None
        if last and last['p'] == b['p'] and (b['s'] - last['e']).total_seconds() <= 600:
            last['e'] = b['e']
            last['pcs'] += b['pcs']
        else:
            merged.append({'p': b['p'], 's': b['s'], 'e': b['e'], 'pcs': list(b['pcs'])})

    def tool_of(app, url, title):
        t = lc(' '.join([title, url]))
        for typ, doms in TOOL_WEB.items():
            if app_is(app, BROWSERS) and any(d in t for d in doms):
                return typ
        for typ, apps in TOOL_APPS.items():
            if app_is(app, apps):
                return typ
        return 'custom'

    # w obrębie bloku projektu dziel wpisy wg narzędzia (np. Figma vs Slack vs faktury),
    # ale tylko gdy dany fragment trwa ≥ 8 min — krótkie przełączenia zostają w sąsiednim wpisie
    split = []
    for b in merged:
        runs = []
        for pc in b['pcs']:
            t = tool_of(pc[2], pc[4], pc[3])
            if runs and runs[-1]['t'] == t:
                runs[-1]['pcs'].append(pc)
            else:
                runs.append({'t': t, 'pcs': [pc]})
        out = []
        for r in runs:
            r_sec = sum((x[1] - x[0]).total_seconds() for x in r['pcs'])
            if out and (r_sec < 480 or out[-1]['t'] == r['t']):
                out[-1]['pcs'] += r['pcs']
            elif not out and r_sec < 480 and len(runs) > 1:
                r['t'] = None  # krótki początek — dołączy do następnego fragmentu
                out.append(r)
            else:
                if out and out[-1]['t'] is None:
                    out[-1]['pcs'] += r['pcs']
                    out[-1]['t'] = r['t']
                else:
                    out.append(r)
        for r in out:
            pcs = sorted(r['pcs'], key=lambda x: x[0])
            split.append({'p': b['p'], 's': pcs[0][0], 'e': pcs[-1][1], 'pcs': pcs})

    entries = []
    for b in split:
        if b['p'] == '_other' and secs(b) < 300:
            continue
        acts = {}
        for x, y, app, title, url, pid, why in b['pcs']:
            domain = re.sub(r'^https?://(www\.)?', '', url).split('/')[0] if url else ''
            k = (app, title or domain)
            a = acts.setdefault(k, {'app': app, 'title': title or domain or app, 'domain': domain, 'seconds': 0, 'tool': tool_of(app, url, title)})
            a['seconds'] += (y - x).total_seconds()
        acts = sorted(acts.values(), key=lambda a: -a['seconds'])
        tool_sec = {}
        for a in acts:
            tool_sec[a['tool']] = tool_sec.get(a['tool'], 0) + a['seconds']
        entries.append({
            'id': f"{b['p']}-{b['s'].astimezone(tz).strftime('%H%M')}",
            'projectId': None if b['p'] == '_other' else b['p'],
            'projectName': names.get(b['p'], 'Inne'),
            'startedAt': b['s'].strftime('%Y-%m-%dT%H:%M:%SZ'), 'endedAt': b['e'].strftime('%Y-%m-%dT%H:%M:%SZ'),
            'from': hm(b['s']), 'to': hm(b['e']),
            'minutes': mins(secs(b)),
            'tool': max(tool_sec, key=tool_sec.get),
            'apps': [{'app': a['app'], 'title': a['title'], 'domain': a['domain'], 'minutes': mins(a['seconds'])} for a in acts[:6]],
            'stillOpen': (datetime.now(timezone.utc) - b['e']).total_seconds() < 900,
        })

    total = sum(P['seconds'] for P in proj.values())
    exported = exp.get('exportedAt')
    print(json.dumps({
        'date': exp.get('date'), 'exportedAt': exported,
        'firstActivity': hm(pieces[0][0]) if pieces else None, 'lastActivity': hm(pieces[-1][1]) if pieces else None,
        'totalMinutes': mins(total), 'hasAfkData': bool(afk), 'hasWebData': bool(web),
        'projects': out_projects, 'timeline': timeline, 'entries': entries,
    }, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
