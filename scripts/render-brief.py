#!/usr/bin/env python3
"""Render a chief-of-staff brief (JSON) as a self-contained HTML page.

Usage:  render-brief.py <brief.json> [out.html]      (default out: same name, .html)
The JSON shape is documented in ~/.ops-agents/templates/brief.schema.md. Unknown keys are ignored;
missing keys render as empty sections, so a partial brief still renders.
"""
import datetime as dt
import html
import json
import pathlib
import sys

P = {"P0": ("Now", "#b42318", "#fef3f2"), "P1": ("Decide", "#b54708", "#fffaeb"), "P2": ("FYI", "#175cd3", "#eff8ff")}
ACTION = {"decide": "decision needed", "approve": "awaiting your go", "review": "review", "none": ""}


def esc(s):
    return html.escape(str(s if s is not None else ""))


def link(text, url):
    return f'<a href="{esc(url)}" target="_blank" rel="noopener">{esc(text)}</a>' if url else esc(text)


def item_row(it):
    p = it.get("priority", "P2")
    label, fg, bg = P.get(p, P["P2"])
    act = it.get("action", "none")
    owner = it.get("owner", "")
    chip = f'<span class="chip" style="color:{fg};background:{bg};border-color:{fg}33">{p} · {label}</span>'
    act_html = f'<span class="act">{esc(ACTION.get(act, act))}</span>' if act and act != "none" else ""
    own = f'<span class="own">{esc(owner)}</span>' if owner else ""
    return f'<li>{chip}<div class="body"><div class="t">{link(it.get("text",""), it.get("link"))}</div><div class="m">{act_html}{own}</div></div></li>'


def section(title, inner, cls=""):
    if not inner:
        return ""
    return f'<section class="{cls}"><h2>{esc(title)}</h2>{inner}</section>'


def ul(items, fmt):
    return "<ul>" + "".join(fmt(i) for i in items) + "</ul>" if items else ""


def render(b):
    ts = b.get("generated_at") or dt.datetime.now().astimezone().isoformat(timespec="minutes")
    items = sorted(b.get("items", []), key=lambda i: ({"P0": 0, "P1": 1, "P2": 2}.get(i.get("priority", "P2"), 3), {"decide": 0, "approve": 1, "review": 2}.get(i.get("action", "none"), 3)))
    n = {k: sum(1 for i in items if i.get("priority") == k) for k in ("P0", "P1", "P2")}
    blind = b.get("not_checked", [])
    clean = b.get("clean", [])
    older = b.get("older", [])
    track = b.get("track", [])
    caps = b.get("capabilities", {})
    conns = b.get("connectors", [])
    headline = b.get("headline", "")
    status = "needs-human" if any(i.get("action") in ("decide", "approve") for i in items) else "ok"
    pill = f'<span class="pill {"warn" if blind else "good"}">{len(blind)} blind spot{"s" if len(blind)!=1 else ""}</span>'
    counts = " ".join(f'<span class="cnt" style="color:{P[k][1]}">{n[k]} {k}</span>' for k in ("P0", "P1", "P2") if n[k])

    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(b.get("title","Brief"))} — {esc(ts[:16])}</title>
<style>
:root{{--bg:#fff;--fg:#1a1a1a;--mut:#666;--line:#e6e6e6;--card:#fafafa}}
@media(prefers-color-scheme:dark){{:root{{--bg:#111;--fg:#eee;--mut:#9a9a9a;--line:#2a2a2a;--card:#181818}}a{{color:#8ab4f8}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,Segoe UI,Inter,system-ui,sans-serif}}
main{{max-width:860px;margin:0 auto;padding:24px 16px 48px}}
header h1{{font-size:22px;margin:0 0 4px}}header .sub{{color:var(--mut);font-size:13px;display:flex;gap:12px;flex-wrap:wrap;align-items:center}}
.pill{{padding:2px 10px;border-radius:999px;font-size:12px;font-weight:600;border:1px solid}}.pill.good{{color:#027a48;background:#ecfdf3;border-color:#027a4833}}.pill.warn{{color:#b54708;background:#fffaeb;border-color:#b5470833}}
.cnt{{font-weight:600}}
.headline{{font-size:17px;margin:18px 0 6px;padding:14px 16px;border-left:4px solid #175cd3;background:var(--card);border-radius:0 8px 8px 0}}
section{{margin-top:26px}}h2{{font-size:13px;letter-spacing:.06em;text-transform:uppercase;color:var(--mut);margin:0 0 10px}}
ul{{list-style:none;margin:0;padding:0}}li{{display:flex;gap:12px;padding:10px 0;border-top:1px solid var(--line);align-items:flex-start}}li:first-child{{border-top:0}}
.chip{{flex:none;font-size:11px;font-weight:700;padding:2px 8px;border-radius:6px;border:1px solid;margin-top:2px;white-space:nowrap}}
.body{{flex:1}}.t{{font-weight:500}}.m{{font-size:12px;color:var(--mut);display:flex;gap:10px;margin-top:2px}}.act{{font-weight:600}}
.blind li{{display:block}}.blind .src{{font-weight:600}}.blind .fix{{color:var(--mut);font-size:13px}}.blind .fix code{{font-size:12px}}
.clean li{{display:block;padding:4px 0;border:0;color:var(--mut)}}.clean li::before{{content:"✓ ";color:#027a48}}
.track{{background:var(--card);border:1px dashed var(--line);border-radius:8px;padding:12px 16px}}.track p{{margin:0 0 8px;font-size:13px;color:var(--mut)}}
.next{{margin-top:28px;padding:14px 16px;border-radius:8px;background:var(--card);border:1px solid var(--line)}}.next b{{display:block;font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em;margin-bottom:4px}}
details{{margin-top:22px;color:var(--mut);font-size:13px}}summary{{cursor:pointer}}pre{{white-space:pre-wrap;font-size:12px}}
footer{{margin-top:32px;font-size:12px;color:var(--mut)}}
table.conn{{width:100%;border-collapse:collapse;font-size:13px}}table.conn th{{text-align:left;font-weight:600;color:var(--mut);font-size:11px;letter-spacing:.04em;text-transform:uppercase;padding:4px 8px 6px 0}}table.conn td{{padding:6px 8px 6px 0;border-top:1px solid var(--line);vertical-align:top}}table.conn tr.failing td:nth-child(3){{color:#b42318;font-weight:600}}table.conn tr.unmapped td:nth-child(3){{color:#b54708;font-weight:600}}table.conn tr.unused td{{color:var(--mut)}}table.conn td.note{{color:var(--mut);font-size:12px}}
</style></head><body><main>
<header><h1>{esc(b.get("title","Brief"))}</h1><div class="sub"><span>{esc(ts)}</span><span>window: {esc(b.get("window",""))}</span>{pill}{counts}<span class="pill {"warn" if status=="needs-human" else "good"}">{status}</span></div></header>
{f'<div class="headline">{esc(headline)}</div>' if headline else ""}
{section("Needs you", ul([i for i in items if i.get("action") in ("decide","approve")], item_row))}
{section("Worth knowing", ul([i for i in items if i.get("action") not in ("decide","approve")], item_row))}
{section("Not checked", ul(blind, lambda x: f'<li><span class="src">{esc(x.get("source",""))}</span> — {esc(x.get("reason",""))}' + (f'<div class="fix">fix: <code>{esc(x.get("fix"))}</code></div>' if x.get("fix") else "") + '</li>'), "blind")}
{section("Came back clean", ul(clean, lambda x: f'<li>{esc(x)}</li>'), "clean")}
{section("Still open from before", ul(older, item_row))}
{section("Connectors", ("<table class=conn><tr><th>Connector</th><th>Capability</th><th>Status</th><th>Agent</th><th></th></tr>" + "".join(f"<tr class={esc(c.get('status',''))}><td>{esc(c.get('name',''))}</td><td>{esc(c.get('capability',''))}</td><td>{esc(c.get('status',''))}</td><td>{esc(c.get('agent',''))}</td><td class=note>{esc(c.get('note',''))}</td></tr>" for c in sorted(conns, key=lambda c: ({'failing':0,'unmapped':1,'used':2,'unused':3}.get(c.get('status',''),4), c.get('name','')))) + "</table>") if conns else "")}
{section("Track?", ('<div class="track"><p>Reply "track" (optionally naming items) to open ledger issues for:</p>' + ul(track, lambda x: f'<li>{esc(x)}</li>') + '</div>') if track else "")}
{f'<div class="next"><b>Next</b>{esc(b.get("next",""))}</div>' if b.get("next") else ""}
<details><summary>Capabilities</summary><pre>{esc(json.dumps(caps, indent=2) if caps else "")}</pre></details>
<footer>chief-of-staff · ops-agents · run log in ~/.ops-agents/runs</footer>
</main></body></html>"""


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    src = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".html")
    b = json.loads(src.read_text())
    out.write_text(render(b))
    print(out)


if __name__ == "__main__":
    main()
