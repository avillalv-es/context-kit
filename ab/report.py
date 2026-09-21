#!/usr/bin/env python3
"""Build the A/B charts (inline SVG) and the HTML summary from results/*.tsv.

No chart library: the marks are simple and hand-written SVG keeps the output a
single self-contained file with nothing fetched, which is the same constraint
the rest of this repo holds itself to.
"""
import csv, html, pathlib, statistics as st

AB = pathlib.Path(__file__).resolve().parent
RES = AB / "results"
OUT = AB / "report"
OUT.mkdir(exist_ok=True)

# Palette: slots 1 and 2 of the validated categorical theme, light/dark pairs.
A_L, B_L = "#2a78d6", "#eb6834"
A_D, B_D = "#3987e5", "#d95926"
GOOD_L, BAD_L = "#008300", "#e34948"
INK, INK2, INK3 = "#0b0b0b", "#52514e", "#77766f"
GRID = "#e4e3df"
SURF = "#fcfcfb"

ARM_LABEL = {"a": "context-kit layout", "b": "one CLAUDE.md"}
TASK_LABEL = {
    "t1": "API field", "t2": "Billing fix", "t3": "DB index", "t4": "Worker guard",
    "t1-api-field": "API field", "t2-billing-fix": "Billing fix",
    "t3-db-index": "DB index", "t4-worker-guard": "Worker guard",
    "T1-api": "API field", "T2-billing": "Billing fix",
    "T3-db": "DB index", "T4-worker": "Worker guard",
}
SIZE_LABEL = {"1": "47 lines", "2": "371 lines", "3": "843 lines"}


def tsv(name):
    p = RES / name
    if not p.exists():
        return []
    with p.open() as f:
        return list(csv.DictReader(f, delimiter="\t"))


def esc(s):
    return html.escape(str(s))


def fmt(n):
    n = float(n)
    return f"{n/1000:.1f}k" if n >= 1000 else f"{n:.0f}"


def axis(x0, y0, w, h, ymax, steps=4, fmtf=fmt):
    """Recessive gridlines + y labels. Returns (svg, yscale)."""
    out = []
    for i in range(steps + 1):
        v = ymax * i / steps
        y = y0 + h - (v / ymax) * h if ymax else y0 + h
        out.append(f'<line x1="{x0}" y1="{y:.1f}" x2="{x0+w}" y2="{y:.1f}" stroke="{GRID}" stroke-width="1"/>')
        out.append(f'<text x="{x0-8}" y="{y+4:.1f}" text-anchor="end" font-size="11" fill="{INK3}">{fmtf(v)}</text>')
    return "".join(out), (lambda v: y0 + h - (float(v) / ymax) * h if ymax else y0 + h)


def legend(right_x, y, items):
    """Right-aligned, level with the title. A legend at the foot of the frame
    gets clipped by every renderer that rounds the viewport down."""
    out = []
    widths = [len(l) * 6.6 + 22 for l, _ in items]
    total = sum(widths) + 18 * (len(items) - 1)
    cx = right_x - total
    for (label, col), wdt in zip(items, widths):
        out.append(f'<rect x="{cx:.1f}" y="{y-9}" width="11" height="11" rx="2.5" fill="{col}"/>')
        out.append(f'<text x="{cx+17:.1f}" y="{y}" font-size="12.5" fill="{INK2}">{esc(label)}</text>')
        cx += wdt + 18
    return "".join(out)


def bar(x, y, w, h, col):
    """Thin mark, 4px rounded data-end, square against the baseline."""
    if h <= 0.5:
        return ""
    r = min(4, h)
    return (f'<path d="M{x},{y+h} L{x},{y+r} Q{x},{y} {x+r},{y} '
            f'L{x+w-r},{y} Q{x+w},{y} {x+w},{y+r} L{x+w},{y+h} Z" fill="{col}"/>')


def svg_open(w, h, title):
    return (f'<svg viewBox="0 0 {w} {h}" width="{w}" height="{h}" xmlns="http://www.w3.org/2000/svg" '
            f'role="img" aria-label="{esc(title)}" font-family="ui-sans-serif,-apple-system,Segoe UI,Roboto,sans-serif">'
            f'<rect width="{w}" height="{h}" fill="{SURF}"/>')


# ---------------------------------------------------------------- chart 1
def chart_curve(static):
    """The headline: context loaded as the monolith grows."""
    W, H = 760, 400
    x0, y0, w, h = 88, 56, 600, 250
    by = {}
    for r in static:
        by.setdefault((r["size"], r["arm"]), []).append(int(r["est_tokens"]))
    sizes = ["1", "2", "3"]
    a = [st.mean(by[(s, "a")]) for s in sizes]
    b = [st.mean(by[(s, "b")]) for s in sizes]
    ymax = max(b) * 1.15
    g, ys = axis(x0, y0, w, h, ymax)
    xs = [x0 + w * i / (len(sizes) - 1) for i in range(len(sizes))]
    s = [svg_open(W, H, "Context loaded as the CLAUDE.md grows")]
    s.append(f'<text x="{x0-56}" y="26" font-size="15" font-weight="600" fill="{INK}">Context a session must load, per task</text>')
    s.append(f'<text x="{x0-56}" y="44" font-size="12" fill="{INK2}">Mean across the four tasks. Estimated tokens.</text>')
    s.append(legend(W - 24, 26, [("one CLAUDE.md", B_L), ("context-kit layout", A_L)]))
    s.append(g)
    for series, col, name in ((b, B_L, "one CLAUDE.md"), (a, A_L, "context-kit layout")):
        pts = " ".join(f"{xs[i]:.1f},{ys(series[i]):.1f}" for i in range(len(sizes)))
        s.append(f'<polyline points="{pts}" fill="none" stroke="{col}" stroke-width="2" stroke-linejoin="round"/>')
        for i in range(len(sizes)):
            s.append(f'<circle cx="{xs[i]:.1f}" cy="{ys(series[i]):.1f}" r="5" fill="{col}" stroke="{SURF}" stroke-width="2"/>')
        s.append(f'<text x="{xs[-1]+12:.1f}" y="{ys(series[-1])+4:.1f}" font-size="12.5" font-weight="600" fill="{INK2}">{fmt(series[-1])}</text>')
    for i, sz in enumerate(sizes):
        s.append(f'<text x="{xs[i]:.1f}" y="{y0+h+22}" text-anchor="middle" font-size="12" fill="{INK2}">{SIZE_LABEL[sz]}</text>')
    s.append(f'<text x="{x0+w/2}" y="{y0+h+44}" text-anchor="middle" font-size="11.5" fill="{INK3}">size of the project&#8217;s CLAUDE.md</text>')
    s.append("</svg>")
    return "".join(s)


# ---------------------------------------------------------------- chart 2
def chart_per_task(static, size="3"):
    W, H = 760, 380
    x0, y0, w, h = 88, 58, 600, 230
    rows = [r for r in static if r["size"] == size]
    tasks = sorted({r["task"] for r in rows})
    ymax = max(int(r["est_tokens"]) for r in rows) * 1.15
    g, ys = axis(x0, y0, w, h, ymax)
    s = [svg_open(W, H, "Context loaded per task")]
    s.append(f'<text x="{x0-56}" y="26" font-size="15" font-weight="600" fill="{INK}">Per task, against an 843-line CLAUDE.md</text>')
    s.append(f'<text x="{x0-56}" y="44" font-size="12" fill="{INK2}">The baseline loads everything every time; the tiered layout loads what matches.</text>')
    s.append(legend(W - 24, 26, [("one CLAUDE.md", B_L), ("context-kit layout", A_L)]))
    s.append(g)
    gw = w / len(tasks)
    bw = min(46, gw / 3)
    for i, t in enumerate(tasks):
        cx = x0 + gw * i + gw / 2
        for j, arm in enumerate(("b", "a")):
            v = next((int(r["est_tokens"]) for r in rows if r["task"] == t and r["arm"] == arm), 0)
            # 2px surface gap between adjacent bars
            bx = cx - bw - 1 + j * (bw + 2)
            s.append(bar(bx, ys(v), bw, y0 + h - ys(v), B_L if arm == "b" else A_L))
            s.append(f'<text x="{bx+bw/2:.1f}" y="{ys(v)-7:.1f}" text-anchor="middle" font-size="11" font-weight="600" fill="{INK2}">{fmt(v)}</text>')
        s.append(f'<text x="{cx:.1f}" y="{y0+h+22}" text-anchor="middle" font-size="12" fill="{INK2}">{esc(TASK_LABEL.get(t,t))}</text>')
    s.append("</svg>")
    return "".join(s)


# ---------------------------------------------------------------- chart 3
def chart_factgap(gap):
    W, H = 760, 360
    x0, y0, w, h = 88, 58, 600, 210
    ymax = max(int(r["facts_armB"]) for r in gap) * 1.18
    g, ys = axis(x0, y0, w, h, ymax, fmtf=lambda v: f"{v:.0f}")
    s = [svg_open(W, H, "Facts placed in front of the agent")]
    s.append(f'<text x="{x0-56}" y="26" font-size="15" font-weight="600" fill="{INK}">Facts actually placed in front of the agent</text>')
    s.append(f'<text x="{x0-56}" y="44" font-size="12" fill="{INK2}">The saving and the risk are the same number.</text>')
    s.append(legend(W - 24, 26, [("one CLAUDE.md", B_L), ("context-kit layout", A_L)]))
    s.append(g)
    gw = w / len(gap)
    bw = min(46, gw / 3)
    for i, r in enumerate(gap):
        cx = x0 + gw * i + gw / 2
        for j, (key, col) in enumerate((("facts_armB", B_L), ("facts_armA", A_L))):
            v = int(r[key])
            bx = cx - bw - 1 + j * (bw + 2)
            s.append(bar(bx, ys(v), bw, y0 + h - ys(v), col))
            s.append(f'<text x="{bx+bw/2:.1f}" y="{ys(v)-7:.1f}" text-anchor="middle" font-size="11" font-weight="600" fill="{INK2}">{v}</text>')
        s.append(f'<text x="{cx:.1f}" y="{y0+h+22}" text-anchor="middle" font-size="12" fill="{INK2}">{esc(TASK_LABEL.get(r["task"], r["task"]))}</text>')
        s.append(f'<text x="{cx:.1f}" y="{y0+h+40}" text-anchor="middle" font-size="11" fill="{INK3}">{r["gap_pct"]}% unseen</text>')
    s.append("</svg>")
    return "".join(s)


# ---------------------------------------------------------------- chart 4
def chart_grades(grades):
    """A pass/fail cell per run. Arms stacked, tasks down, repetitions across."""
    if not grades:
        return ""
    tasks = [t for t in ("t1", "t2", "t3", "t4")
             if any(g["task"] == t for g in grades)]
    reps = sorted({g["rep"] for g in grades})
    if not tasks or not reps:
        return ""

    cw, ch, gap, row = 34, 22, 6, 28
    gutter = 150
    block = row * len(tasks) + 22          # heading + its rows
    W = 760
    top = 78
    H = top + block * 2 + 34

    s = [svg_open(W, H, "Correctness of every run")]
    s.append(f'<text x="32" y="26" font-size="15" font-weight="600" fill="{INK}">'
             f'Correctness, every run</text>')
    s.append(f'<text x="32" y="46" font-size="12" fill="{INK2}">Graded against the '
             f'load-bearing convention for each task, not just &#8220;does it run&#8221;.</text>')

    for ai, arm in enumerate(("b", "a")):
        by = top + ai * block
        s.append(f'<text x="32" y="{by}" font-size="12.5" font-weight="600" fill="{INK2}">'
                 f'{esc(ARM_LABEL[arm])}</text>')
        for ti, t in enumerate(tasks):
            cy = by + 12 + ti * row
            s.append(f'<text x="{gutter-12}" y="{cy+ch-6}" text-anchor="end" font-size="11.5" '
                     f'fill="{INK3}">{esc(TASK_LABEL.get(t, t))}</text>')
            for ri, rep in enumerate(reps):
                g = next((x for x in grades
                          if x["task"] == t and x["arm"] == arm and x["rep"] == rep), None)
                cx = gutter + ri * (cw + gap)
                col = GRID if not g else (GOOD_L if g["verdict"] == "PASS" else BAD_L)
                s.append(f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" rx="4" fill="{col}"/>')
                if g:
                    mark = "&#10003;" if g["verdict"] == "PASS" else "&#10007;"
                    s.append(f'<text x="{cx+cw/2}" y="{cy+ch/2+4.5}" text-anchor="middle" '
                             f'font-size="12" font-weight="700" fill="#ffffff">{mark}</text>')
            passed = sum(1 for x in grades
                         if x["task"] == t and x["arm"] == arm and x["verdict"] == "PASS")
            total = sum(1 for x in grades if x["task"] == t and x["arm"] == arm)
            tx = gutter + len(reps) * (cw + gap) + 8
            s.append(f'<text x="{tx}" y="{cy+ch-6}" font-size="11.5" fill="{INK3}">'
                     f'{passed}/{total}</text>')

    s.append(f'<text x="32" y="{H-12}" font-size="11.5" fill="{INK3}">'
             f'{len(reps)} repetitions per task &#183; green = followed the convention, '
             f'red = did not</text>')
    s.append("</svg>")
    return "".join(s)


# ---------------------------------------------------------------- chart 5
def chart_empirical(emp, runs):
    """Every run, not a mean. Peak context = the largest the model's window got.

    Both arms pay an identical fixed floor (system prompt + harness + tool
    schemas) before any project file is read. The floor is drawn so the reader
    can see how much of each bar the layout could possibly have influenced.
    """
    if not emp:
        return ""
    rows = [r for r in emp if r.get("peak_ctx")]
    if not rows:
        return ""
    W, H = 760, 424
    x0, y0, w, h = 96, 96, 580, 210
    peaks = [float(r["peak_ctx"]) for r in rows]
    ymax = max(peaks) * 1.15
    floor = min(peaks)
    g, ys = axis(x0, y0, w, h, ymax)
    s = [svg_open(W, H, "Peak context per run")]
    s.append(f'<text x="18" y="26" font-size="15" font-weight="600" fill="{INK}">Peak context per run</text>')
    s.append(f'<text x="18" y="44" font-size="12" fill="{INK2}">Largest context window each agent occupied. Every run shown; three per task per arm.</text>')
    s.append(legend(W - 18, 26, [(ARM_LABEL["b"], B_L), (ARM_LABEL["a"], A_L)]))
    s.append(g)

    tasks = [t for t in ("t1", "t2", "t3", "t4")
             if any(r["task"] == t for r in rows)]
    if not tasks:
        return ""
    slot = w / len(tasks)
    bw = min(15.0, (slot - 26) / 7.0)
    for ti, t in enumerate(tasks):
        cx = x0 + slot * (ti + 0.5)
        n = 0
        for arm in ("b", "a"):
            reps = sorted((r for r in rows if r["task"] == t and r["arm"] == arm),
                          key=lambda r: r["rep"])
            for r in reps:
                v = float(r["peak_ctx"])
                bx = cx - (bw * 7) / 2 + n * (bw + 2)
                col = B_L if arm == "b" else A_L
                s.append(bar(bx, ys(v), bw, y0 + h - ys(v), col))
                n += 1
            n += 1  # gutter between the two arms
        s.append(f'<text x="{cx:.1f}" y="{y0+h+22}" text-anchor="middle" '
                 f'font-size="12" fill="{INK2}">{esc(TASK_LABEL.get(t, t))}</text>')

    fy = ys(floor)
    s.append(f'<rect x="{x0}" y="{fy:.1f}" width="{w}" height="{y0+h-fy:.1f}" '
             f'fill="{INK3}" opacity="0.07"/>')
    s.append(f'<line x1="{x0}" y1="{fy:.1f}" x2="{x0+w}" y2="{fy:.1f}" '
             f'stroke="{INK3}" stroke-width="1" stroke-dasharray="4 3"/>')
    s.append(f'<text x="{x0}" y="{y0+h+44}" font-size="11.5" fill="{INK3}">'
             f'shaded band = the &#8776;{fmt(floor)} fixed floor (system prompt, harness, '
             f'tool schemas) that both arms pay before reading any project file</text>')

    # the per-arm medians, stated rather than drawn, so the eye is not asked
    # to average bars it cannot average
    def med(arm):
        v = sorted(float(r["peak_ctx"]) for r in rows if r["arm"] == arm)
        return v[len(v) // 2] if v else 0
    ma, mb = med("a"), med("b")
    if ma and mb:
        delta = (mb - ma) / mb * 100
        s.append(f'<text x="{x0}" y="{y0+h+66}" font-size="11.5" fill="{INK3}">'
                 f'median peak &#183; one CLAUDE.md {fmt(mb)} &#183; context-kit {fmt(ma)} '
                 f'&#183; {delta:.0f}% lower, N={len(rows)} runs</text>')
    s.append("</svg>")
    return "".join(s)


def build():
    static = tsv("static.tsv")
    gap = tsv("factgap.tsv")
    grades = tsv("grades.tsv")
    emp = tsv("empirical.tsv")
    runs = tsv("runs.tsv")
    charts = {
        "01-curve": chart_curve(static) if static else "",
        "02-per-task": chart_per_task(static) if static else "",
        "03-fact-gap": chart_factgap(gap) if gap else "",
        "04-correctness": chart_grades(grades),
        "05-tokens": chart_empirical(emp, runs),
    }
    for name, svg in charts.items():
        if svg:
            (OUT / f"{name}.svg").write_text(svg)
            (OUT / f"{name}.html").write_text(
                f'<!DOCTYPE html><meta charset="utf-8">'
                f'<body style="margin:0;padding:0;overflow:hidden;background:{SURF}">{svg}</body>')
    return charts, static, gap, grades, emp, runs


if __name__ == "__main__":
    c, *_ = build()
    print("charts:", ", ".join(k for k, v in c.items() if v))


# ---------------------------------------------------------------- summary
SUMMARY_CSS = """
:root{color-scheme:light;--bg:#fcfcfb;--panel:#f4f3f0;--line:#e4e3df;--ink:#0b0b0b;
--ink2:#52514e;--ink3:#77766f;--a:#2a78d6;--b:#eb6834;--good:#008300;--bad:#e34948;--warn:#b4530a}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#1a1a19;--panel:#232321;
--line:#34332f;--ink:#fff;--ink2:#c3c2b7;--ink3:#96958c;--a:#3987e5;--b:#d95926;--good:#3ddc97;
--bad:#e66767;--warn:#f0a15c}}
:root[data-theme="dark"]{--bg:#1a1a19;--panel:#232321;--line:#34332f;--ink:#fff;--ink2:#c3c2b7;
--ink3:#96958c;--a:#3987e5;--b:#d95926;--good:#3ddc97;--bad:#e66767;--warn:#f0a15c}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--ink);font:15px/1.6 ui-sans-serif,-apple-system,"Segoe UI",Roboto,sans-serif;
padding:48px 16px 96px}
main{max-width:860px;margin:0 auto}
h1{font-size:30px;line-height:1.2;letter-spacing:-.02em;margin-bottom:10px}
h2{font-size:20px;margin:44px 0 12px;letter-spacing:-.01em}
h3{font-size:15px;margin:26px 0 8px;color:var(--ink2)}
p{margin-bottom:14px;color:var(--ink2)}
.lede{font-size:17px;color:var(--ink2);margin-bottom:8px}
.meta{font-size:13px;color:var(--ink3);margin-bottom:28px}
figure{margin:22px 0;background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px;overflow-x:auto}
figure svg{display:block;max-width:100%;height:auto}
figcaption{font-size:12.5px;color:var(--ink3);margin-top:10px;padding:0 4px}
table{border-collapse:collapse;width:100%;font-size:13.5px;margin:14px 0}
th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--line)}
th{color:var(--ink3);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.05em}
td.num{text-align:right;font-variant-numeric:tabular-nums}
.k{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px 18px;margin:18px 0}
.k b{display:block;font-size:13px;color:var(--ink3);text-transform:uppercase;letter-spacing:.05em;margin-bottom:6px}
.big{font-size:30px;font-weight:650;letter-spacing:-.02em;color:var(--ink)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px;margin:18px 0}
.pass{color:var(--good);font-weight:600}.fail{color:var(--bad);font-weight:600}
.caveat{border-left:3px solid var(--warn);padding:12px 16px;background:var(--panel);border-radius:0 8px 8px 0;margin:18px 0}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em;background:var(--panel);
padding:1px 5px;border-radius:4px}
ul{margin:0 0 14px 20px;color:var(--ink2)}li{margin-bottom:6px}
@media(max-width:700px){body{padding:28px 14px 64px}h1{font-size:24px}}
"""


def summary_html(charts, static, gap, grades, emp, runs):
    def fig(key, cap):
        if not charts.get(key):
            return ""
        return f'<figure>{charts[key]}<figcaption>{cap}</figcaption></figure>'

    s3 = [r for r in static if r["size"] == "3"]
    b3 = st.mean([int(r["est_tokens"]) for r in s3 if r["arm"] == "b"]) if s3 else 0
    a3 = st.mean([int(r["est_tokens"]) for r in s3 if r["arm"] == "a"]) if s3 else 0
    cut = (1 - a3 / b3) * 100 if b3 else 0

    npass = {a: sum(1 for g in grades if g["arm"] == a and g["verdict"] == "PASS") for a in "ab"}
    ntot = {a: sum(1 for g in grades if g["arm"] == a) for a in "ab"}

    o = [f'<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">',
         '<meta name="viewport" content="width=device-width,initial-scale=1">',
         '<title>Context Layout A/B</title>', f'<style>{SUMMARY_CSS}</style></head><body><main>']
    o.append('<h1>Does a three-tier context layout beat one CLAUDE.md?</h1>')
    o.append('<p class="lede">Same project, same facts, two shapes. One monolithic '
             '<code>CLAUDE.md</code> against context-kit&#8217;s tier-1 router plus '
             'path-scoped rules.</p>')
    o.append('<p class="meta">meterflow &#183; 31 files &#183; 4 tasks &#215; 2 arms &#215; 3 repetitions '
             '&#183; generated from <code>ab/results/*.tsv</code></p>')

    o.append('<div class="grid">')
    o.append(f'<div class="k"><b>Context per task</b><div class="big">&#8722;{cut:.0f}%</div>'
             f'<p style="margin:4px 0 0;font-size:13px">{fmt(b3)} &#8594; {fmt(a3)} est. tokens, '
             f'against an 843-line CLAUDE.md</p></div>')
    if gap:
        mg = st.mean([float(r["gap_pct"]) for r in gap])
        o.append(f'<div class="k"><b>Facts withheld</b><div class="big">{mg:.0f}%</div>'
                 f'<p style="margin:4px 0 0;font-size:13px">never shown to the agent &#8212; '
                 f'the saving and the risk are one number</p></div>')
    if ntot.get("a") and ntot.get("b"):
        o.append(f'<div class="k"><b>Correctness</b><div class="big">{npass["a"]}/{ntot["a"]} '
                 f'vs {npass["b"]}/{ntot["b"]}</div>'
                 f'<p style="margin:4px 0 0;font-size:13px">tiered vs monolithic, graded on the '
                 f'convention each task turns on</p></div>')
    o.append('</div>')

    o.append('<h2>What was measured, and how hard the number is</h2>')
    o.append('<p>Two layers, and they are not equally strong. The deterministic layer is exact and '
             're-runnable: it counts the bytes of project context each layout forces a session to '
             'load. The empirical layer runs a real model on real tasks, and at three repetitions '
             'per cell it can only tell you whether an effect is large enough to be obvious.</p>')
    o.append('<p>Both arms are generated from the same <code>blocks/</code> directory, so they hold '
             'identical facts by construction. <code>verify-parity.sh</code> asserts it at every '
             'size, and it passes.</p>')

    o.append('<h2>The deterministic result</h2>')
    o.append(fig("01-curve",
                 'The gap is a function of how bloated the CLAUDE.md is. On a tidy 47-line file the '
                 'tiered layout saves little; on an 843-line one it loads a fraction. This is the '
                 'whole claim, and it is arithmetic rather than opinion.'))
    o.append(fig("02-per-task",
                 'Per task. The baseline pays the same price every time because it has no mechanism '
                 'to pay less. The tiered layout pays for what the task touches.'))

    if static:
        o.append('<h3>Every figure behind those charts</h3><table><tr><th>CLAUDE.md</th><th>Task</th>'
                 '<th class="num">one CLAUDE.md</th><th class="num">context-kit</th>'
                 '<th class="num">reduction</th></tr>')
        for size in ("1", "2", "3"):
            for t in sorted({r["task"] for r in static}):
                bv = next((int(r["est_tokens"]) for r in static if r["size"] == size and r["task"] == t and r["arm"] == "b"), 0)
                av = next((int(r["est_tokens"]) for r in static if r["size"] == size and r["task"] == t and r["arm"] == "a"), 0)
                red = (1 - av / bv) * 100 if bv else 0
                o.append(f'<tr><td>{SIZE_LABEL[size]}</td><td>{esc(TASK_LABEL.get(t,t))}</td>'
                         f'<td class="num">{bv:,}</td><td class="num">{av:,}</td>'
                         f'<td class="num">{red:.0f}%</td></tr>')
        o.append('</table>')
        o.append('<p style="font-size:13px;color:var(--ink3)">Tokens estimated at 4 bytes each. '
                 '<code>knowledge/</code> counts as zero for the tiered arm because tier 3 is reached '
                 'by lookup &#8212; that is the claim under test, not a neutral accounting choice.</p>')

    o.append('<h2>The other side of the same number</h2>')
    o.append(fig("03-fact-gap",
                 'Every fact the tiered layout does not load is a fact the agent cannot use. Whether '
                 'that matters depends entirely on whether the withheld facts were load-bearing for '
                 'the task &#8212; which is what the correctness grading tests.'))
    o.append('<div class="caveat"><p style="margin:0"><b>This is the honest risk.</b> Withholding '
             '81&#8211;94% of the project&#8217;s written knowledge is the mechanism by which the '
             'saving happens. It is only a good trade if the routing is right. A rule whose '
             '<code>paths:</code> glob misses the file being edited is a fact silently withheld, and '
             'nothing in the layout will tell you it happened.</p></div>')
    return o



def summary_tail(o, charts, static, gap, grades, emp, runs):
    def fig(key, cap):
        if not charts.get(key):
            return ""
        return f'<figure>{charts[key]}<figcaption>{cap}</figcaption></figure>'

    o.append('<h2>The empirical result</h2>')
    if not emp and not grades:
        o.append('<p>Not yet run.</p>')
        return o

    def col(rows, arm, key):
        return [float(r[key]) for r in rows if r["arm"] == arm]

    def median(v):
        v = sorted(v)
        if not v:
            return 0.0
        n = len(v)
        return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2

    if emp:
        o.append(fig("05-tokens",
                     "Peak context per run. Every run is a bar; the shaded band is the fixed "
                     "floor both arms pay before reading anything."))
        pa, pb = col(emp, "a", "peak_ctx"), col(emp, "b", "peak_ctx")
        if pa and pb:
            ma, mb = median(pa), median(pb)
            d = (1 - ma / mb) * 100
            o.append(f'<p>Median peak context was <b>{fmt(ma)}</b> for the tiered layout against '
                     f'<b>{fmt(mb)}</b> for the single file &#8212; <b>{abs(d):.0f}% '
                     f'{"lower" if d > 0 else "higher"}</b>, across {len(pa)} and {len(pb)} runs. '
                     f'Spread was {fmt(min(pa))}&#8211;{fmt(max(pa))} and '
                     f'{fmt(min(pb))}&#8211;{fmt(max(pb))}.</p>')
            floor = min(pa + pb)
            above_a, above_b = ma - floor, mb - floor
            if above_b > 0:
                o.append(f'<div class="caveat"><p style="margin:0"><b>Most of both bars is not the '
                         f'layout.</b> Roughly {fmt(floor)} of every run is fixed overhead &#8212; '
                         f'system prompt, harness, tool schemas &#8212; paid identically by both '
                         f'arms. Measured against only the part a layout can move, the gap is '
                         f'{fmt(above_a)} against {fmt(above_b)}. The percentage above is the '
                         f'honest whole-window figure; this is the honest mechanism figure. '
                         f'Neither is a benchmark at N={len(pa) + len(pb)}.</p></div>')
            if abs(d) < 10:
                o.append('<div class="caveat"><p style="margin:0"><b>Read that as noise, not as a '
                         'result.</b> A difference this size sits inside the run-to-run variation '
                         'the fixed overhead produces, and three repetitions cannot separate '
                         'the two.</p></div>')

        o.append('<h3>Every run</h3>')
        o.append('<p>No means hidden. <code>peak</code> is the largest context the model held; '
                 '<code>new</code> is material written into context across the run; '
                 '<code>files</code> is distinct project files opened, counted from the '
                 'transcript rather than the ledger, because agents read through '
                 '<code>cat</code> and <code>grep</code> as often as through the file tool.</p>')
        o.append('<table><tr><th>Task</th><th>Arm</th><th>Rep</th><th class="num">peak</th>'
                 '<th class="num">new</th><th class="num">tool calls</th>'
                 '<th class="num">files</th></tr>')
        for r in sorted(emp, key=lambda r: (r["task"], r["arm"], r["rep"])):
            o.append(f'<tr><td>{esc(TASK_LABEL.get(r["task"], r["task"]))}</td>'
                     f'<td>{esc(ARM_LABEL[r["arm"]])}</td><td>{esc(r["rep"])}</td>'
                     f'<td class="num">{fmt(float(r["peak_ctx"]))}</td>'
                     f'<td class="num">{fmt(float(r["new_ctx"]))}</td>'
                     f'<td class="num">{esc(r["tools"])}</td>'
                     f'<td class="num">{esc(r["files"])}</td></tr>')
        o.append('</table>')

        fa, fb = col(emp, "a", "files"), col(emp, "b", "files")
        if fa and fb:
            aa, ab = sum(fa) / len(fa), sum(fb) / len(fb)
            if aa > ab:
                o.append(f'<p><b>The tradeoff the token count hides.</b> The tiered arm opened '
                         f'{aa:.1f} distinct files per run against the baseline&#8217;s {ab:.1f}. '
                         f'It reads <i>more files</i> to read <i>less text</i>. If your cost model '
                         f'counts tool calls rather than tokens, that is a real cost and it points '
                         f'the other way.</p>')
            else:
                o.append(f'<p>The tiered arm opened {aa:.1f} distinct files per run against the '
                         f'baseline&#8217;s {ab:.1f}, so on this project the layout did not cost '
                         f'extra navigation.</p>')

    if grades:
        o.append('<h2>Correctness</h2>')
        o.append(fig("04-correctness",
                     'Each task turns on one written convention. A run that produces working code '
                     'while breaking that convention is scored wrong, because that is the failure '
                     'the convention exists to prevent.'))
        o.append('<table><tr><th>Task</th><th>Turns on</th><th>one CLAUDE.md</th>'
                 '<th>context-kit</th></tr>')
        TURNS = {
            "t1": "energy in a response is kWh, via <code>toKwh</code>",
            "t2": "tariff precedence <code>capacity &gt; timeOfUse &gt; fixed</code>",
            "t3": "never edit an applied migration; <code>CREATE INDEX CONCURRENTLY</code>",
            "t4": "batch limits come from config, never a literal",
        }
        for t in ("t1", "t2", "t3", "t4"):
            cells = []
            for a in ("b", "a"):
                gs = [g for g in grades if g["task"] == t and g["arm"] == a]
                p = sum(1 for g in gs if g["verdict"] == "PASS")
                cls = "pass" if p == len(gs) and gs else ("fail" if p == 0 else "")
                cells.append(f'<td class="{cls}">{p}/{len(gs)}</td>')
            o.append(f'<tr><td>{esc(TASK_LABEL[t])}</td><td>{TURNS[t]}</td>{"".join(cells)}</tr>')
        o.append('</table>')
        fails = [g for g in grades if g["verdict"] != "PASS"]
        if fails:
            o.append('<h3>Every failure, with its reason</h3><ul>')
            for g in fails:
                o.append(f'<li><b>{esc(TASK_LABEL[g["task"]])}</b>, {esc(ARM_LABEL[g["arm"]])}, '
                         f'run {esc(g["rep"])} &#8212; {esc(g["reason"])}</li>')
            o.append('</ul>')
        else:
            o.append('<p>No run in either arm broke the convention its task turned on.</p>')
    return o


def summary_method(o):
    o.append('<h2>Method, and what it does not support</h2>')
    o.append('<h3>Design</h3><ul>')
    o.append('<li>Both arms are generated from one <code>blocks/</code> directory, so they hold the '
             'same facts by construction. <code>verify-parity.sh</code> asserts it and passes at all '
             'three sizes.</li>')
    o.append('<li>Prompts are identical except the directory. Neither agent was told an experiment '
             'was running, or which arm it was in.</li>')
    o.append('<li>Each of the 24 runs got its own clean working copy.</li>')
    o.append('<li>context-kit&#8217;s hook-injected ruleset fired for <b>both</b> arms, identically. '
             'It is a constant and cannot explain any gap between them.</li>')
    o.append('<li>Empirical numbers come from the subagent transcripts, not from context-kit&#8217;s '
             'own activity ledger. The ledger only sees the file-reading tool, and these agents '
             'read through <code>cat</code> and <code>grep</code> far more often, so the ledger '
             'undercounts by a wide margin. <code>peak</code> is '
             '<code>input + cache_creation + cache_read</code> at its maximum over a run &#8212; '
             'the largest the context window actually got.</li>')
    o.append('</ul>')
    o.append('<h3>What this cannot tell you</h3><ul>')
    o.append('<li><b>Three repetitions per cell.</b> Enough to notice a large effect, nowhere near '
             'enough to measure a small one, and not a benchmark.</li>')
    o.append('<li><b>One project, one model, one session.</b> The project was written for this test, '
             'which means its knowledge is unusually well-organised into areas &#8212; exactly the '
             'condition the tiered layout is best at. A repo whose conventions cut across areas '
             'would route worse.</li>')
    o.append('<li><b>The deterministic layer counts what a layout <i>forces</i> a session to load</b>, '
             'not what a model chooses to read. An agent that reads the whole repo anyway defeats '
             'the layout, and nothing here prevents that.</li>')
    o.append('<li><b><code>knowledge/</code> is counted as zero</b> for the tiered arm. That is the '
             'model&#8217;s claim, and it is the single assumption most likely to flatter it.</li>')
    o.append('</ul>')
    o.append('<h3>Reproducing it</h3>')
    o.append('<p>Everything is in <code>ab/</code>: <code>measure-static.sh</code> for the exact '
             'numbers, <code>verify-parity.sh</code> for the fairness check, <code>factgap.sh</code> '
             'for the withheld-facts count, <code>grade.sh</code> for correctness, <code>collect-tokens.py</code> for the per-run telemetry, '
             '<code>report.py</code> to rebuild these charts. The raw TSVs every figure is drawn '
             'from are in <code>ab/results/</code>.</p>')
    o.append('</main></body></html>')
    return o


def build_summary():
    charts, static, gap, grades, emp, runs = build()
    o = summary_html(charts, static, gap, grades, emp, runs)
    o = summary_tail(o, charts, static, gap, grades, emp, runs)
    o = summary_method(o)
    p = OUT / "summary.html"
    p.write_text("".join(o))
    return p
