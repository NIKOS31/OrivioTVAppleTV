"""Summarize an `xctrace export` time-profile table: the app's main thread only.

Output is code symbols and milliseconds, nothing from the app's content.
Streaming parse: xctrace writes each thread/weight/frame/backtrace once with
an id and later rows point at it with ref=.
"""
import collections
import json
import sys
import xml.etree.ElementTree as ET

path, label, test = sys.argv[1], sys.argv[2], sys.argv[3]
threads, weights, binaries, frames, backtraces = {}, {}, {}, {}, {}


def resolve(elem, table, build):
    ref = elem.get("ref")
    if ref is not None:
        return table.get(ref)
    value = build(elem)
    if elem.get("id") is not None:
        table[elem.get("id")] = value
    return value


def build_binary(e):
    return e.get("name") or "?"


def build_frame(e):
    b = e.find("binary")
    return (e.get("name") or e.get("addr") or "?", resolve(b, binaries, build_binary) if b is not None else "?")


def build_backtrace(e):
    return [resolve(f, frames, build_frame) for f in e.findall("frame")]


total_ns = main_ns = 0
self_ns = collections.Counter()
incl_ns = collections.Counter()
app_incl_ns = collections.Counter()
app_self_ns = collections.Counter()
samples = 0
for _, elem in ET.iterparse(path, events=("end",)):
    if elem.tag != "row":
        continue
    t = elem.find("thread")
    w = elem.find("weight")
    bt = elem.find("backtrace")
    thread = resolve(t, threads, lambda e: e.get("fmt") or "") if t is not None else ""
    weight = resolve(w, weights, lambda e: int(e.text or 0)) if w is not None else 0
    stack = resolve(bt, backtraces, build_backtrace) if bt is not None else None
    elem.clear()
    total_ns += weight or 0
    if not thread.startswith("Main Thread") or not stack or not weight:
        continue
    samples += 1
    main_ns += weight
    self_ns[stack[0][0]] += weight
    seen, seen_app = set(), set()
    for name, binary in stack:
        if name not in seen:
            seen.add(name)
            incl_ns[name] += weight
        if "OrivioTV" in (binary or "") and name not in seen_app:
            seen_app.add(name)
            app_incl_ns[name] += weight
    for name, binary in stack:
        if "OrivioTV" in (binary or ""):
            app_self_ns[name] += weight
            break


def top(counter, n):
    return [{"symbol": k[:240], "ms": round(v / 1e6, 1), "share": round(v / main_ns, 3) if main_ns else None}
            for k, v in counter.most_common(n)]


print(json.dumps({
    "label": label, "test": test,
    "environment": "simulateur tvOS, build Debug, GitHub Actions; pas une mesure Apple TV",
    "mainThreadMs": round(main_ns / 1e6, 1), "allThreadsMs": round(total_ns / 1e6, 1), "mainSamples": samples,
    "topSelf": top(self_ns, 40),
    "topInclusive": top(incl_ns, 120),
    "appInclusive": top(app_incl_ns, 60),
    "appInnermost": top(app_self_ns, 40),
}, indent=1, ensure_ascii=False))
if not samples:
    raise SystemExit("No main-thread sample found.")
